#!/bin/bash

set -e  # Detener ejecución si hay errores

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funciones de logging
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

# Función para manejar errores
handle_error() {
    log_error "Error en línea $1. Comando que falló: $2"
    log_error "Abortando instalación..."
    exit 1
}

# Configurar trap para manejar errores
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

echo "🚀 INICIANDO INSTALACIÓN DE C-NETWORK-AGENT"
echo "=============================================="

# Detectar sistema operativo
log_info "Detectando sistema operativo..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    DIST=$VERSION_CODENAME
    log_success "Sistema detectado: $PRETTY_NAME ($OS $DIST)"
else
    log_error "No se pudo detectar el sistema operativo"
    exit 1
fi

# Verificar que sea Ubuntu o Debian
if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    log_error "Este script solo funciona en Ubuntu o Debian"
    exit 1
fi

# Limpiar repositorios Docker existentes que puedan causar conflictos
log_info "Limpiando repositorios Docker existentes..."
rm -f /usr/share/keyrings/docker-archive-keyring.gpg
rm -f /usr/share/keyrings/docker.gpg
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/sources.list.d/docker.ce.list

# Limpiar cualquier configuración de Docker previa en sources.list
if grep -q "download.docker.com" /etc/apt/sources.list; then
    log_info "Removiendo entradas Docker de sources.list principal..."
    sed -i '/download\.docker\.com/d' /etc/apt/sources.list
fi

# Actualizar el sistema
log_info "Actualizando sistema..."
apt-get update -y || {
    log_warning "Primera actualización falló, intentando limpiar cache y repositorios problemáticos..."
    apt-get clean
    
    # Remover repositorios problemáticos temporalmente
    if [ -d /etc/apt/sources.list.d/ ]; then
        mkdir -p /tmp/disabled-repos
        find /etc/apt/sources.list.d/ -name "*docker*" -exec mv {} /tmp/disabled-repos/ \;
    fi
    
    apt-get update -y || {
        log_error "No se pudo actualizar la lista de paquetes después de limpieza"
        exit 1
    }
}

# Instalar paquetes necesarios
log_info "Instalando paquetes del sistema..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    fping \
    vsftpd \
    tftpd-hpa

log_info "Instalando Docker..."

# Determinar la URL correcta según el OS
if [ "$OS" = "ubuntu" ]; then
    DOCKER_URL="https://download.docker.com/linux/ubuntu"
    GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
elif [ "$OS" = "debian" ]; then
    DOCKER_URL="https://download.docker.com/linux/debian"
    GPG_URL="https://download.docker.com/linux/debian/gpg"
fi

log_info "Configurando repositorio Docker para $OS..."

# Asegurar que no hay configuraciones previas
log_info "Limpiando cualquier configuración Docker previa..."
rm -f /usr/share/keyrings/docker-archive-keyring.gpg
rm -f /usr/share/keyrings/docker.gpg
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/sources.list.d/docker.ce.list

# Añadir la clave GPG oficial de Docker
log_info "Descargando clave GPG de Docker..."
if curl -fsSL "$GPG_URL" | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg; then
    log_success "Clave GPG de Docker descargada correctamente"
else
    log_error "No se pudo descargar la clave GPG de Docker"
    exit 1
fi

# Verificar que la clave se descargó correctamente
if [ ! -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
    log_error "La clave GPG de Docker no se guardó correctamente"
    exit 1
fi

# Añadir el repositorio de Docker
log_info "Añadiendo repositorio Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $DOCKER_URL \
  $DIST stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Verificar que el archivo se creó correctamente
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    log_error "No se pudo crear el archivo de repositorio Docker"
    exit 1
fi

log_success "Repositorio Docker configurado correctamente"

# Actualizar el sistema nuevamente
log_info "Actualizando lista de paquetes con repositorio Docker..."
if apt-get update -y; then
    log_success "Lista de paquetes actualizada correctamente"
else
    log_error "Error al actualizar después de agregar repositorio Docker"
    log_info "Contenido del repositorio Docker:"
    cat /etc/apt/sources.list.d/docker.list
    exit 1
fi

# Instalar Docker
log_info "Instalando Docker Engine..."

# Verificar si Docker ya está instalado
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version 2>/dev/null || echo "desconocida")
    log_warning "Docker ya está instalado: $DOCKER_VERSION"
    log_info "Continuando con la instalación actual..."
fi

# Instalar o actualizar Docker
if apt-get install -y docker-ce docker-ce-cli containerd.io; then
    log_success "Docker Engine instalado/actualizado correctamente"
else
    log_error "Error al instalar Docker Engine"
    log_info "Intentando con repositorio alternativo..."
    
    # Método alternativo usando snap como fallback
    if command -v snap &> /dev/null; then
        log_info "Intentando instalación via snap..."
        if snap install docker; then
            log_success "Docker instalado via snap"
        else
            log_error "Falló instalación via snap también"
            exit 1
        fi
    else
        log_error "No hay métodos alternativos disponibles"
        exit 1
    fi
fi

# Instalar Docker Compose
log_info "Instalando Docker Compose..."

# Verificar si Docker Compose ya está instalado
if command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "desconocida")
    log_warning "Docker Compose ya está instalado (versión $COMPOSE_VERSION)"
    log_info "Actualizando a la versión más reciente..."
fi

# Intentar instalar via apt primero (más confiable en sistemas modernos)
if apt-get install -y docker-compose-plugin; then
    log_success "Docker Compose Plugin instalado via apt"
    # Crear symlink para compatibilidad
    if [ ! -f /usr/local/bin/docker-compose ]; then
        ln -s /usr/bin/docker-compose /usr/local/bin/docker-compose 2>/dev/null || true
    fi
else
    log_info "Plugin no disponible, descargando binario..."
    
    # Obtener la última versión desde GitHub API
    LATEST_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")' 2>/dev/null || echo "v2.24.0")
    COMPOSE_URL="https://github.com/docker/compose/releases/download/${LATEST_VERSION}/docker-compose-$(uname -s)-$(uname -m)"
    
    log_info "Descargando Docker Compose ${LATEST_VERSION}..."
    
    if curl -L "$COMPOSE_URL" -o /usr/local/bin/docker-compose; then
        chmod +x /usr/local/bin/docker-compose
        log_success "Docker Compose instalado correctamente"
    else
        log_warning "Fallo descarga de versión latest, usando versión fallback..."
        FALLBACK_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)"
        if curl -L "$FALLBACK_URL" -o /usr/local/bin/docker-compose; then
            chmod +x /usr/local/bin/docker-compose
            log_success "Docker Compose fallback instalado"
        else
            log_error "No se pudo descargar Docker Compose"
            exit 1
        fi
    fi
fi

# Verificar instalación
if command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version 2>/dev/null || echo "Error obteniendo versión")
    log_success "Docker Compose verificado: $COMPOSE_VERSION"
else
    log_error "Docker Compose no se instaló correctamente"
    exit 1
fi

log_info "Creando directorios para datos persistentes..."

# Crear directorios para volúmenes persistentes
mkdir -p /data/influxdb2
mkdir -p /data/mongodb
mkdir -p /data/files
mkdir -p /data/redis

# Establecer permisos
chown -R 1000:1000 /data/influxdb2
chown -R 1000:1000 /data/mongodb
chown -R 1000:1000 /data/files

log_success "Directorios de datos creados correctamente"

log_info "Configurando servicios FTP y TFTP..."

# Configurar FTP (vsftpd)
log_info "Configurando vsftpd..."
CONFIG_URL="https://raw.githubusercontent.com/Crenein/cnetwork-agent-install/master/vsftpd.conf"

if wget "$CONFIG_URL" -O vsftpd.conf; then
    # Eliminar archivo viejo de configuración
    rm -f /etc/vsftpd.conf
    # Mover el archivo de configuración descargado
    mv vsftpd.conf /etc/
    # Reiniciar servicio vsftpd
    systemctl restart vsftpd
    systemctl enable vsftpd
    log_success "vsftpd configurado correctamente"
else
    log_warning "No se pudo descargar configuración de vsftpd, usando configuración por defecto"
fi

# Crear usuario para backups y establecer permisos
if ! id "backups" &>/dev/null; then
    useradd -M -d /data/files backups
    log_success "Usuario 'backups' creado"
else
    log_info "Usuario 'backups' ya existe"
fi

chown backups:backups -R /data/files
chmod 755 -R /data/files

# Configurar TFTP (tftpd-hpa)
log_info "Configurando tftpd-hpa..."
TFTP_CONFIG_URL="https://raw.githubusercontent.com/Crenein/cnetwork-agent-install/master/tftpd-hpa"

if wget "$TFTP_CONFIG_URL" -O tftpd-hpa; then
    # Eliminar archivo de configuración existente
    rm -f /etc/default/tftpd-hpa
    # Mover el archivo de configuración descargado
    mv tftpd-hpa /etc/default/
    # Reiniciar servicio tftpd-hpa
    systemctl restart tftpd-hpa
    systemctl enable tftpd-hpa
    log_success "tftpd-hpa configurado correctamente"
else
    log_warning "No se pudo descargar configuración de tftpd-hpa, usando configuración por defecto"
fi

log_info "Creando archivos de configuración..."

# Crear el archivo .env
cat > .env << 'EOL'
INFLUX_TOKEN="dVrF7ocM2YMc4s2ueWUP18lQr6VrEY3VIxIZhNk28bT-EVJCC05njToMjpeklm0whFZIiobjbZFxNTyLXsP5Cg=="
INFLUX_BUCKET=fping
INFLUX_URL="http://influxdb:8086"
SECRET_KEY="09d25e094faa6ca2556c818166b7a9563b93f7099f6f0f4caa6cf63b88e8d3e7"
ALGORITHM="HS256"
ACCESS_TOKEN_EXPIRE_MINUTES=30
DEBUG=False
DB_NAME=mongo-agent
DB_URL=mongodb://root:root@mongodb:27017/?authSource=admin&tls=false
KEY_ENCRYPT=b'y1TpxOK9wYrdMT0ti9pK2NTuhw0DlrOGYrpTsl26f70='
FERNET_KEY='y1TpxOK9wYrdMT0ti9pK2NTuhw0DlrOGYrpTsl26f70='
REDIS_URL=redis://redis:6379/0
EOL

# Crear el archivo docker-compose.yml
cat > docker-compose.yml << 'EOL'
version: '3.8'
services:
  influxdb:
    image: influxdb:2.0
    ports:
      - "8086:8086"
    restart: always
    volumes:
      - /data/influxdb2:/var/lib/influxdb2
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=admin
      - DOCKER_INFLUXDB_INIT_PASSWORD=CreneinLocal
      - DOCKER_INFLUXDB_INIT_ORG=crenein
      - DOCKER_INFLUXDB_INIT_BUCKET=fping
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=dVrF7ocM2YMc4s2ueWUP18lQr6VrEY3VIxIZhNk28bT-EVJCC05njToMjpeklm0whFZIiobjbZFxNTyLXsP5Cg==
    networks:
      - app-network

  mongodb:
    image: mongo:7.0
    container_name: mongodb
    ports:
      - "27017:27017"
    restart: always
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: root
    volumes:
      - /data/mongodb:/data/db
    networks:
      - app-network

  redis:
    image: redis:7.2
    container_name: redis
    restart: always
    ports:
      - "6379:6379"
    volumes:
      - /data/redis:/data
    command: ["redis-server", "--appendonly", "yes", "--maxmemory", "256mb", "--maxmemory-policy", "allkeys-lru"]
    networks:
      - app-network
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'

  cnetwork-agent:
    image: crenein/c-network-agent:latest
    container_name: cnetwork-agent
    ports:
      - "8000:8000"
    restart: always
    env_file:
      - .env
    volumes:
      - /data/files:/app/files
    networks:
      - app-network
    depends_on:
      - influxdb
      - mongodb
      - redis
    deploy:
      resources:
        limits:
          memory: 1.5G
          cpus: '1.5'
        reservations:
          memory: 512M
          cpus: '0.5'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  dramatiq-worker:
    image: crenein/c-network-agent:latest
    container_name: dramatiq-worker
    restart: always
    env_file:
      - .env
    volumes:
      - /data/files:/app/files
    networks:
      - app-network
    depends_on:
      - redis
      - cnetwork-agent
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
        reservations:
          memory: 512M
          cpus: '0.5'
    command: ["dramatiq", "worker_poller", "--processes", "2", "--threads", "5"]

networks:
  app-network:
    driver: bridge
EOL

# Asegurarse de que Docker esté iniciado
log_info "Iniciando servicios Docker..."

# Verificar y corregir permisos de Docker socket
if [ -S /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock 2>/dev/null || true
fi

systemctl start docker
systemctl enable docker

# Esperar a que Docker esté completamente iniciado
sleep 5

# Verificar que Docker está funcionando
if ! docker --version &> /dev/null; then
    log_error "Docker no se instaló correctamente"
    log_info "Intentando diagnóstico..."
    systemctl status docker --no-pager
    exit 1
fi

# Verificar que Docker daemon está corriendo
if ! docker info &> /dev/null; then
    log_warning "Docker daemon no responde, intentando reiniciar..."
    systemctl restart docker
    sleep 10
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon no está corriendo después de reiniciar"
        systemctl status docker --no-pager
        journalctl -u docker --no-pager -n 20
        exit 1
    fi
fi

log_success "Docker instalado y funcionando correctamente"

# Verificar que Docker Compose funciona
if ! docker-compose --version &> /dev/null; then
    log_error "Docker Compose no está funcionando"
    exit 1
fi

# Verificar conectividad con Docker Hub
log_info "Verificando conectividad con Docker Hub..."
if timeout 30 docker pull hello-world &> /dev/null; then
    docker rmi hello-world &> /dev/null
    log_success "Conectividad con Docker Hub verificada"
else
    log_warning "Problemas de conectividad con Docker Hub. Verificando..."
    
    # Intentar con un registry alternativo o continuar
    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_warning "Internet disponible pero problemas con Docker Hub. Continuando..."
    else
        log_error "Sin conectividad a internet"
        exit 1
    fi
fi

# Crear y arrancar los contenedores
log_info "Iniciando contenedores..."
if docker-compose up -d; then
    log_success "Contenedores iniciados correctamente"
else
    log_error "Error al iniciar contenedores"
    docker-compose logs
    exit 1
fi

# Función para verificar que un contenedor esté saludable
check_container_health() {
    local container_name=$1
    local max_attempts=30
    local attempt=0
    
    log_info "Verificando salud del contenedor $container_name..."
    while [ $attempt -lt $max_attempts ]; do
        if docker ps --filter "name=$container_name" --filter "status=running" | grep -q $container_name; then
            log_success "$container_name está corriendo"
            return 0
        fi
        attempt=$((attempt + 1))
        log_info "Intento $attempt/$max_attempts - Esperando que $container_name esté listo..."
        sleep 2
    done
    log_error "$container_name no está saludable después de $max_attempts intentos"
    
    # Mostrar logs del contenedor que falló
    log_error "Logs del contenedor $container_name:"
    docker logs $container_name 2>/dev/null || log_warning "No se pudieron obtener logs de $container_name"
    return 1
}

# Verificar que los contenedores estén saludables
log_info "Verificando que los servicios estén listos..."

# Verificar contenedores en orden de dependencias
check_container_health "influxdb" || exit 1
check_container_health "mongodb" || exit 1
check_container_health "redis" || exit 1

# Esperar un poco más para que los servicios se inicialicen
log_info "Esperando inicialización de servicios base..."
sleep 10

check_container_health "cnetwork-agent" || exit 1
check_container_health "dramatiq-worker" || exit 1

# Esperar adicional para que los servicios se inicialicen completamente
log_info "Esperando inicialización completa de servicios..."
sleep 20

# Verificar que el endpoint de salud responda
log_info "Verificando endpoint de salud..."
max_health_attempts=15
health_attempt=0

while [ $health_attempt -lt $max_health_attempts ]; do
    if curl -f http://localhost:8000/health &> /dev/null; then
        log_success "Endpoint de salud respondiendo correctamente"
        break
    fi
    health_attempt=$((health_attempt + 1))
    log_info "Intento $health_attempt/$max_health_attempts - Esperando endpoint de salud..."
    sleep 3
done

if [ $health_attempt -eq $max_health_attempts ]; then
    log_warning "Endpoint de salud no responde, verificando si el contenedor está corriendo..."
    docker ps | grep cnetwork-agent || {
        log_error "Contenedor cnetwork-agent no está corriendo"
        docker logs cnetwork-agent
        exit 1
    }
    log_warning "Continuando con la instalación..."
fi

# Ejecutar el comando en el contenedor cnetwork-agent
log_info "Ejecutando script de poblado de base de datos..."
retry_count=0
max_retries=3

while [ $retry_count -lt $max_retries ]; do
    if docker exec cnetwork-agent python3 populate_db.py; then
        log_success "Base de datos inicializada correctamente"
        break
    else
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log_warning "Error al inicializar BD. Intento $retry_count/$max_retries. Reintentando en 10 segundos..."
            sleep 10
        else
            log_error "Error al inicializar la base de datos después de $max_retries intentos"
            log_info "Logs del contenedor cnetwork-agent:"
            docker logs cnetwork-agent
            exit 1
        fi
    fi
done

# Verificación final del estado de los contenedores
log_info "Verificación final del estado de contenedores..."
if docker-compose ps | grep -q "Exit\|Restarting"; then
    log_warning "Algunos contenedores pueden tener problemas:"
    docker-compose ps
else
    log_success "Todos los contenedores están funcionando correctamente"
fi

echo ""
log_success "🎉 ¡INSTALACIÓN COMPLETADA EXITOSAMENTE!"
echo ""
log_info "📋 INFORMACIÓN DEL SISTEMA:"
echo "   - FastAPI: http://localhost:8000"
echo "   - InfluxDB: http://localhost:8086"
echo "   - MongoDB: localhost:27017"
echo "   - Redis: localhost:6379"
echo ""
echo ""
log_info "🔑 CREDENCIALES:"
echo "   - Admin: agent@example.com / admin123"
echo "   - InfluxDB: admin / CreneinLocal"
echo ""
log_info "📝 COMANDOS ÚTILES:"
echo "   - Verificar estado: docker-compose ps"
echo "   - Ver logs: docker-compose logs -f"
echo "   - Reiniciar servicios: docker-compose restart"
echo "   - Detener servicios: docker-compose down"
echo ""
log_success "Sistema listo para monitorear hasta 10 dispositivos de red"
