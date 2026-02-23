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

get_env_value() {
  local key="$1"
  awk -F= -v k="$key" '
    $0 !~ /^[[:space:]]*#/ && $0 ~ "^"k"=" {
      sub("^"k"=", "", $0);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0);
      if ($0 ~ /^".*"$/) { sub(/^"/, "", $0); sub(/"$/, "", $0) }
      if ($0 ~ /^\x27.*\x27$/) { sub(/^\x27/, "", $0); sub(/\x27$/, "", $0) }
      print $0
    }
  ' "$ENV_FILE" | tail -n 1
}

require_bcrypt_hash() {
  local var_name="$1"
  local value
  value="$(get_env_value "$var_name")"

  if [[ -z "$value" ]]; then
    echo "ERROR: Falta $var_name en $ENV_FILE (requerido para Caddy basic_auth)"
    exit 1
  fi

  if [[ ! "$value" =~ ^\$2[aby]\$ ]] || (( ${#value} < 50 )); then
    echo "ERROR: $var_name no parece un hash bcrypt válido (ej: \$2a\$14\$...)"
    echo "Genera uno con: docker run --rm caddy:2 caddy hash-password --plaintext 'TU_PASSWORD'"
    exit 1
  fi
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

require_bcrypt_hash "MINIO_CONSOLE_PASSWORD_HASH"

echo "Pull de imágenes..."
compose pull

echo "Asegurando servicios base arriba (db/redis/minio/frontends/caddy)..."
compose up -d postgres redis minio allyapp ally360-web caddy

echo "Ejecutando migraciones (one-shot service)..."
compose run --rm migrations

echo "Validando migraciones en Postgres (alembic_version + users)..."
if ! compose exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "select to_regclass('"'"'public.alembic_version'"'"')" | grep -q alembic_version'; then
  echo "ERROR: alembic_version no existe después de migrar"
  exit 1
fi

if ! compose exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "select to_regclass('"'"'public.users'"'"')" | grep -q users'; then
  echo "ERROR: users no existe después de migrar (evita relation \"users\" does not exist)"
  exit 1
fi

echo "Rolling update API: api-b -> api-a"
compose up -d --no-deps --force-recreate api-b
wait_healthy api-b 240

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
