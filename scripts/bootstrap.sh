#!/usr/bin/env bash
set -euo pipefail

# Ubuntu bootstrap for EC2
# - Instala Docker + Docker Compose plugin
# - Clona este repo en /opt/ally360/deploy-manager
# - Copia env desde ubicación segura (no se versiona)
# - Levanta el stack

REPO_URL="${REPO_URL:-https://github.com/ally-360/deploy-manager.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/ally360/deploy-manager}"
ENV_SOURCE="${ENV_SOURCE:-/opt/ally360/secrets/ally360.env}"
ENV_TARGET_REL="${ENV_TARGET_REL:-env/.env}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: ejecuta como root (sudo)"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "Instalando dependencias base..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg git

echo "Instalando Docker + Compose plugin..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "$SUDO_USER" || true
fi

echo "Clonando/actualizando repo..."
mkdir -p "$(dirname "$INSTALL_DIR")"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" fetch --all --prune
  git -C "$INSTALL_DIR" pull --ff-only
else
  rm -rf "$INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
mkdir -p "$(dirname "$ENV_TARGET_REL")"

if [[ ! -f "$ENV_SOURCE" ]]; then
  echo "ERROR: No existe ENV_SOURCE=$ENV_SOURCE"
  echo "Crea el archivo de secretos fuera del repo, por ejemplo:"
  echo "  sudo mkdir -p /opt/ally360/secrets"
  echo "  sudo cp /ruta/segura/ally360.env $ENV_SOURCE"
  echo "Luego re-ejecuta este script, o exporta ENV_SOURCE antes de correrlo."
  exit 1
fi

echo "Copiando env (desde ubicación segura) ..."
cp "$ENV_SOURCE" "$ENV_TARGET_REL"
chmod 600 "$ENV_TARGET_REL" || true

echo "Levantando stack..."
docker compose --env-file "$ENV_TARGET_REL" -f docker-compose.prod.yml up -d

echo "Bootstrap OK"
