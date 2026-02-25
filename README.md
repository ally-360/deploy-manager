# Ally360 Deploy Manager (AWS EC2 + Docker Compose + Caddy)

Este repo contiene lo necesario para desplegar Ally360 en una instancia EC2 (Ubuntu) usando Docker Compose y Caddy como reverse proxy con TLS automático (Let's Encrypt).

## Arquitectura

- **Caddy (80/443)**: TLS + reverse proxy por dominios.
- **API**: 2 réplicas (`api-a` y `api-b`) detrás de Caddy.
- **Celery**: `celery-worker` y `celery-beat`.
- **Infra**: PostgreSQL, Redis, MinIO (S3 compatible).
- **Frontends**:
	- `app.ally360.co` → `allyapp` (imagen `ghcr.io/ally-360/webpage-platform:latest`)
	- `ally360.co` / `www.ally360.co` → `ally360-web` (TODO: imagen aún no publicada)

## Requisitos

- EC2 Ubuntu 22.04+ (recomendado)
- DNS apuntando a la IP pública de la instancia:
	- `api.ally360.co`
	- `app.ally360.co`
	- `s3.ally360.co`
	- `console.ally360.co`
	- `ally360.co` y `www.ally360.co`
- Security Group con:
	- inbound `TCP 80` desde 0.0.0.0/0
	- inbound `TCP 443` desde 0.0.0.0/0
	- (opcional) SSH restringido a tu IP

## TODO: imagen de homepage (ally360-web)

La imagen `ghcr.io/ally-360/ally360-web` aún no está publicada (según el estado actual).

Hasta que exista:
- Publica la imagen y setea `ALLY360_WEB_IMAGE` (recomendado), o
- Deshabilita temporalmente el servicio `ally360-web` en `docker-compose.prod.yml` y su host en `caddy/Caddyfile`.

## Archivos principales

- [docker-compose.prod.yml](docker-compose.prod.yml)
- [caddy/Caddyfile](caddy/Caddyfile)
- [scripts/bootstrap.sh](scripts/bootstrap.sh)
- [scripts/deploy.sh](scripts/deploy.sh)
- [env/.env.example](env/.env.example)

## GitHub Actions (deploy automático)

Workflow: [.github/workflows/deploy-to-ec2.yml](.github/workflows/deploy-to-ec2.yml)

Secrets requeridos en el repo `deploy-manager`:

- `EC2_HOST` (IP o hostname público, idealmente Elastic IP)
- `EC2_USER` (por defecto `ubuntu`)
- `EC2_SSH_KEY` (private key PEM para SSH)
- `GHCR_USER`
- `GHCR_TOKEN` (PAT con `read:packages`)

Disparadores:

- `workflow_dispatch` (manual) con input `image_tag` (default: `latest`)
- `push` a `main`
- `repository_dispatch` (tipo `deploy`) para que otros repos disparen un deploy centralizado

### Enfoque recomendado (otros repos → deploy-manager)

En vez de que cada repo (backend/frontend/homepage) haga SSH al servidor, publica las imágenes en GHCR en sus propios pipelines y luego dispara el deploy de `deploy-manager` usando `repository_dispatch`.

Ventajas:
- Centralizas el deploy y los secretos EC2/GHCR en un solo repo.
- Los repos de build solo “notifican” un `image_tag`.

Ejemplo desde otro repo (luego de publicar `ghcr.io/ally-360/ally360-api:<TAG>`):

```bash
curl -fsSL -X POST \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: Bearer $DEPLOY_MANAGER_TOKEN" \
	https://api.github.com/repos/ally-360/deploy-manager/dispatches \
	-d '{"event_type":"deploy","client_payload":{"image_tag":"'"$TAG"'"}}'
```

Notas:
- `DEPLOY_MANAGER_TOKEN` debe ser un PAT (o token fine-grained) con permiso para llamar `repository_dispatch` sobre `ally-360/deploy-manager`.
- Si no quieres duplicar ese token en cada repo, usa un **Organization secret** compartido.

Estructura:

- `docker-compose.prod.yml`
- `caddy/Caddyfile`
- `scripts/bootstrap.sh`
- `scripts/deploy.sh`
- `env/.env.example`

## Variables de entorno

1) Copia la plantilla y ajusta valores:

```bash
mkdir -p env
cp env/.env.example env/.env
```

2) Variables mínimas recomendadas (producción):

- `CADDY_EMAIL` (para Let's Encrypt)
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
- `APP_SECRET_STRING` (JWT/signing)
- `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`
- `MINIO_PUBLIC_HOST=s3.ally360.co`, `MINIO_PUBLIC_PORT=443`, `MINIO_PUBLIC_USE_SSL=true`
- `FRONTEND_URL=https://app.ally360.co`
- `ENVIRONMENT=production`, `DEBUG=false`, `AUTO_RUN_MIGRATIONS=false`
- Para deploy desde GHCR:
	- `GHCR_USER`
	- `GHCR_TOKEN` (PAT con `read:packages`)

Notas:
- `env/.env` **no** se versiona (ver `.gitignore`).
- El tag del backend se controla con `IMAGE_TAG` (por defecto `latest`).
- La imagen de homepage aún está en TODO; por ahora el servicio usa `ALLY360_WEB_IMAGE`.

Seguridad:
- `console.ally360.co` está protegido por Basic Auth (Caddy). Define `MINIO_CONSOLE_PASSWORD_HASH` (bcrypt).

Homepage (`ally360.co` / `www.ally360.co`):
- Imagen esperada: `ghcr.io/ally-360/ally360-web:latest`.
- Se recomienda publicarla desde el repo `webpage-platform` y disparar el deploy de este repo con `repository_dispatch`.

## Bootstrap en EC2 (primera vez)

En el servidor:

```bash
curl -fsSL https://raw.githubusercontent.com/ally-360/deploy-manager/main/scripts/bootstrap.sh -o bootstrap.sh
chmod +x bootstrap.sh

# Opcional: sobreescribir repo/env-source
# REPO_URL="https://github.com/ally-360/deploy-manager.git" ENV_SOURCE="/opt/ally360/secrets/ally360.env" sudo -E ./bootstrap.sh

sudo -E ./bootstrap.sh
```

El script:
- instala Docker + plugin de Compose
- clona el repo en `/opt/ally360/deploy-manager`
- copia el `.env` desde una ubicación segura (`/opt/ally360/secrets/ally360.env` por defecto)
- levanta el stack con `docker compose`

## Deploy (actualizaciones)

En el servidor (o en tu pipeline), desde `/opt/ally360/deploy-manager`:

```bash
chmod +x scripts/deploy.sh

# Deploy usando último tag (default: latest)
GHCR_USER=... GHCR_TOKEN=... ./scripts/deploy.sh

# Deploy usando un tag específico para la API
GHCR_USER=... GHCR_TOKEN=... ./scripts/deploy.sh 2026-02-22
```

Notas:
- El script hace rolling update: sube `api-b` → espera health → sube `api-a` → espera health.
- Ejecuta migraciones **una sola vez** con el servicio one-shot `migrations` (Alembic upgrade head).
- Reinicia `celery-worker` y `celery-beat`.
- Recarga Caddy (sin tumbar TLS).

Importante:
- No expone puertos públicos de Postgres/Redis/MinIO (solo internos; Caddy publica por dominios).
- No hace `FLUSHDB` de Redis.

## Troubleshooting rápido

- Ver estado: `docker compose --env-file env/.env -f docker-compose.prod.yml ps`
- Logs API: `docker logs ally360-api-a --tail 200` / `docker logs ally360-api-b --tail 200`
- Validar health: `curl -fsS https://api.ally360.co/health`