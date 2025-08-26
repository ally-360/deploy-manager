# Local Development Stack

Este stack levanta el entorno completo de desarrollo local con los siguientes servicios:

- **Auth Service** + PostgreSQL + Keycloak (autenticación y autorización)
- **Storage Service** + MinIO (almacenamiento de archivos)
- Bases de datos PostgreSQL independientes
- Servidor de identidades Keycloak con realm pre-configurado

## Requisitos
- Docker Desktop
- macOS con shell zsh

## Uso

```bash
cd deploy-manager/local

# Primera vez: configurar variables de entorno
cp .env.example .env
# Editar .env si es necesario (los valores por defecto funcionan)

# Primera vez (o si cambias dependencias)
docker compose build

# Levantar todo el stack
docker compose up -d

# Ver logs de todos los servicios
docker compose logs -f

# Ver logs de un servicio específico
docker compose logs -f auth-service
docker compose logs -f storage-service
docker compose logs -f minio
docker compose logs -f keycloak

# Detener todo
docker compose down

# Limpiar todo (incluyendo volúmenes)
docker compose down -v
```

## Servicios disponibles

Una vez que el stack esté ejecutándose, tendrás acceso a:

### 🔐 Auth Service
- **API**: http://localhost:4000
- **Swagger**: http://localhost:4000/api
- **Health**: http://localhost:4000/v1/auth/health

### 🗃️ Storage Service
- **API**: http://localhost:4001
- **Swagger**: http://localhost:4001/api
- **Health**: http://localhost:4001/health

### 🔑 Keycloak (Servidor de identidades)
- **Admin Console**: http://localhost:8080
- **Usuario**: admin
- **Contraseña**: admin
- **Realm**: ally (pre-configurado)

### 🗄️ MinIO (Almacenamiento de objetos)
- **Console**: http://localhost:9001
- **API**: http://localhost:9000
- **Usuario**: minioadmin
- **Contraseña**: minioadmin123

### 🐘 Bases de datos PostgreSQL
- **Auth DB**: `postgres://auth_user:auth_password@localhost:5432/auth-service`
- **Keycloak DB**: `postgres://keycloak:keycloak@localhost:5433/keycloak`

## Ejemplos de uso

### Subir un archivo al Storage Service
```bash
curl -X POST http://localhost:4001/storage/upload \
  -F "file=@/path/to/your/file.pdf" \
  -F "bucket=documents"
```

### Obtener token de Keycloak
```bash
curl -X POST http://localhost:8080/realms/ally/protocol/openid-connect/token \
  -d "grant_type=password" \
  -d "client_id=ally-api" \
  -d "username=test@example.com" \
  -d "password=test1234"
```

## Notas importantes

- **Hot-reload**: El código de ambos servicios (`auth-service` y `storage-service`) está montado como volumen para desarrollo con hot-reload
- **Configuración**: Las variables de entorno se leen desde `deploy-manager/local/.env`
- **Datos persistentes**: Los datos de PostgreSQL y MinIO se almacenan en volúmenes Docker
- **Usuario de prueba**: Se crea automáticamente un usuario `test@example.com` con contraseña `test1234`
- **Buckets**: El bucket `storage` se crea automáticamente en MinIO

## Troubleshooting

### Si un servicio no arranca:
```bash
# Ver logs del servicio específico
docker compose logs SERVICE_NAME

# Reiniciar un servicio
docker compose restart SERVICE_NAME

# Reconstruir si hay cambios en Dockerfile
docker compose build SERVICE_NAME
```

### Si hay problemas de conectividad:
```bash
# Verificar que todos los contenedores estén ejecutándose
docker compose ps

# Verificar redes
docker network ls
```

### Limpiar completamente el entorno:
```bash
# Detener y eliminar todo (incluyendo volúmenes)
docker compose down -v

# Eliminar imágenes construidas
docker compose build --no-cache
```
