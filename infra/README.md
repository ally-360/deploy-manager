# Infra (Serverless Framework + CloudFormation) — EC2 para Ally360

Este directorio aprovisiona infraestructura en AWS usando **Serverless Framework** (archivo `serverless.yml`) como wrapper de **CloudFormation**, pero **sin AWS Lambda**.

## Qué crea

- 1x EC2 (Ubuntu 22.04 LTS) para correr Docker Compose.
- 1x Elastic IP (IP fija) + asociación a la instancia.
- 1x Security Group:
  - 80/tcp público (0.0.0.0/0)
  - 443/tcp público (0.0.0.0/0)
  - 22/tcp **solo** a tu IP (`MY_IP_CIDR`)
- Disco root EBS **gp3 80GB** (BlockDeviceMappings).
- UserData idempotente:
  - instala Docker + Docker Compose plugin
  - clona `deploy-manager` a `/opt/ally360/deploy-manager`
  - **no** ejecuta `docker compose up` si no existe `env/.env` (deja log claro)

## Nota sobre VPC/Subnet

CloudFormation no puede “descubrir” la VPC por defecto sin un custom resource. Para que el despliegue sea reproducible y sin dependencias, este template crea una **VPC pública mínima** (1 subnet pública + IGW + route table).

Si prefieres usar la VPC por defecto, se puede ajustar el template para recibir `VpcId/SubnetId` como parámetros.

## Prerrequisitos

1) AWS credentials configuradas localmente:

- `aws configure` (o variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`)
- Permisos para crear EC2/VPC/EIP/SecurityGroup/RouteTable

2) Crear un **Key Pair** en la región objetivo (NO se crea aquí):

- EC2 → Key Pairs → Create key pair
- Guarda el `.pem`

3) Tener tu IP pública (para SSH):

- `MY_IP_CIDR` ejemplo: `190.x.x.x/32`

4) Instalar dependencias de `infra/` (fija Serverless v3 para evitar el requisito de login/licencia de v4):

```bash
cd infra
npm install
```

## Deploy

Desde este directorio (`deploy-manager/infra`):

```bash
npx serverless deploy --stage prod
```

Parámetros requeridos (mínimos):

```bash
npx serverless deploy --stage prod \
  --param="KEY_NAME=tu-keypair" \
  --param="MY_IP_CIDR=190.x.x.x/32"
```

Opcional (sobre-escribir defaults):

```bash
npx serverless deploy --stage prod \
  --param="KEY_NAME=tu-keypair" \
  --param="MY_IP_CIDR=190.x.x.x/32" \
  --param="REGION=us-east-1" \
  --param="INSTANCE_TYPE=t3a.small" \
  --param="REPO_URL=https://github.com/ally-360/deploy-manager.git" \
  --param="REPO_BRANCH=main"
```

Outputs esperados:
- `ElasticIP`
- `InstanceId`

## Remove

```bash
npx serverless remove --stage prod
```

## Post-deploy (pasos en el servidor)

1) Asigna DNS en Spaceship apuntando a la **Elastic IP** (A records):

- `api.ally360.co`
- `app.ally360.co`
- `s3.ally360.co`
- `console.ally360.co`
- `ally360.co` y `www.ally360.co`

2) SSH a la instancia:

```bash
ssh -i /ruta/tu-keypair.pem ubuntu@<ELASTIC_IP>
```

3) Preparar `env/.env`:

```bash
cd /opt/ally360/deploy-manager
cp env/.env.example env/.env
vi env/.env
```

4) Login a GHCR (para imágenes privadas):

```bash
export GHCR_USER=...
export GHCR_TOKEN=...   # PAT con read:packages
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
```

5) Deploy del stack (rolling update + migraciones + celery):

```bash
chmod +x scripts/deploy.sh
GHCR_USER="$GHCR_USER" GHCR_TOKEN="$GHCR_TOKEN" ./scripts/deploy.sh

# o con tag específico para backend:
GHCR_USER="$GHCR_USER" GHCR_TOKEN="$GHCR_TOKEN" ./scripts/deploy.sh 2026-02-22
```

## Ver logs del bootstrap

En la instancia:

```bash
sudo tail -n 200 /var/log/ally360-bootstrap.log
```
