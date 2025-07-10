#!/bin/bash

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

handle_error() {
    log_error "Error en línea $1. Comando que falló: $2"
    log_error "Abortando actualización..."
    exit 1
}

trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

log_info "🔄 Iniciando actualización de C-Network Agent..."

# Verificar que docker-compose.yml existe
if [ ! -f docker-compose.yml ]; then
    log_error "No se encontró docker-compose.yml en el directorio actual. Ejecuta este script en la carpeta de instalación."
    exit 1
fi

# Descargar las últimas imágenes
log_info "📥 Descargando últimas imágenes de Docker..."
docker pull crenein/c-network-agent:fastapi
docker pull crenein/c-network-agent:celery-worker
docker pull crenein/c-network-agent:celery-beat
docker pull crenein/c-network-agent:flower

# Detener los servicios actuales
log_info "🛑 Deteniendo servicios actuales..."
docker compose down

# Levantar los servicios con las nuevas imágenes
log_info "🚀 Levantando servicios actualizados..."
docker compose up -d

# Verificar estado de los contenedores
log_info "🔎 Verificando estado de los contenedores..."
docker compose ps

log_success "🎉 Actualización completada. El sistema está corriendo con las últimas imágenes."
log_info "Puedes verificar los logs con: docker compose logs -f [servicio]"
