#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-env/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: No existe $ENV_FILE"
  echo "Crea el archivo desde la plantilla: cp env/.env.example $ENV_FILE"
  exit 1
fi

if [[ -n "${1:-}" ]]; then
  export IMAGE_TAG="$1"
fi

: "${GHCR_USER:?Missing GHCR_USER}"
: "${GHCR_TOKEN:?Missing GHCR_TOKEN}"

echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

wait_healthy() {
  local service="$1"
  local timeout_seconds="${2:-180}"

  local start_ts
  start_ts="$(date +%s)"

  while true; do
    local container_id
    container_id="$(compose ps -q "$service" | head -n 1)"
    if [[ -z "$container_id" ]]; then
      echo "Esperando contenedor para $service..."
    else
      local status
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container_id" 2>/dev/null || true)"
      if [[ "$status" == "healthy" ]]; then
        echo "$service está healthy"
        return 0
      fi
      if [[ "$status" == "unhealthy" ]]; then
        echo "ERROR: $service está unhealthy"
        docker logs "$container_id" --tail 200 || true
        return 1
      fi
      echo "Esperando health de $service (status=$status)..."
    fi

    if (( $(date +%s) - start_ts > timeout_seconds )); then
      echo "ERROR: timeout esperando health de $service"
      return 1
    fi
    sleep 3
  done
}

echo "Pull de imágenes..."
compose pull

echo "Asegurando servicios base arriba (db/redis/minio/frontends/caddy)..."
compose up -d postgres redis minio allyapp ally360-web caddy

echo "Rolling update API: api-b -> api-a"
compose up -d --no-deps --force-recreate api-b
wait_healthy api-b 240

echo "Ejecutando migraciones (una sola vez)..."
compose run --rm api-b python migrate.py upgrade

compose up -d --no-deps --force-recreate api-a
wait_healthy api-a 240

echo "Recreando Celery (worker/beat)..."
compose up -d --no-deps --force-recreate celery-worker celery-beat

echo "Recargando Caddy..."
if ! compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile; then
  echo "WARN: reload falló; reiniciando caddy"
  compose restart caddy
fi

echo "Limpieza de imágenes..."
docker image prune -f

echo "Validando health público..."
curl -fsS https://api.ally360.co/health >/dev/null
echo "Deploy OK"
