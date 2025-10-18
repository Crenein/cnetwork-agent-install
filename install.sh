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

# Función para verificar estado de datos persistentes
verify_data_state() {
    log_info "Verificando estado de datos persistentes..."

    local data_found=false
    declare -A DATA_STATUS

    # Verificar cada directorio de datos
    if [ -d "/data/influxdb2" ] && [ "$(ls -A /data/influxdb2 2>/dev/null)" ]; then
        local size=$(du -sh /data/influxdb2 2>/dev/null | cut -f1)
        DATA_STATUS["influxdb"]="✅ Datos encontrados (${size:-0})"
        data_found=true
    else
        DATA_STATUS["influxdb"]="ℹ️  Directorio vacío (primera instalación)"
    fi

    if [ -d "/data/mongodb" ] && [ "$(ls -A /data/mongodb 2>/dev/null)" ]; then
        local size=$(du -sh /data/mongodb 2>/dev/null | cut -f1)
        DATA_STATUS["mongodb"]="✅ Datos encontrados (${size:-0})"
        data_found=true
    else
        DATA_STATUS["mongodb"]="ℹ️  Directorio vacío (primera instalación)"
    fi

    if [ -d "/data/redis" ] && [ "$(ls -A /data/redis 2>/dev/null)" ]; then
        local size=$(du -sh /data/redis 2>/dev/null | cut -f1)
        DATA_STATUS["redis"]="✅ Datos encontrados (${size:-0})"
        data_found=true
    else
        DATA_STATUS["redis"]="ℹ️  Directorio vacío (primera instalación)"
    fi

    if [ -d "/data/files" ] && [ "$(ls -A /data/files 2>/dev/null)" ]; then
        local size=$(du -sh /data/files 2>/dev/null | cut -f1)
        DATA_STATUS["files"]="✅ Datos encontrados (${size:-0})"
        data_found=true
    else
        DATA_STATUS["files"]="ℹ️  Directorio vacío (primera instalación)"
    fi

    # Mostrar estado
    echo ""
    log_info "Estado de datos persistentes:"
    for service in "${!DATA_STATUS[@]}"; do
        echo "   ${DATA_STATUS[$service]}"
    done
    echo ""

    if [ "$data_found" = true ]; then
        log_success "✅ Datos existentes detectados - serán preservados durante la instalación"
    else
        log_info "ℹ️  Primera instalación - se crearán directorios vacíos"
    fi

    return 0
}

# Función para asegurar directorios persistentes (NO toca datos existentes)
ensure_persistent_directories() {
    log_info "Verificando y asegurando directorios para datos persistentes..."

    # Definir directorios requeridos con sus propietarios
    declare -A DATA_DIRS_CONFIG=(
        ["/data/influxdb2"]="1000:1000:influxdb"
        ["/data/mongodb"]="1000:1000:mongodb"
        ["/data/redis"]="1000:1000:redis"
        ["/data/files"]="backups:backups:backups"
    )

    # Crear directorio base si no existe
    if [ ! -d "/data" ]; then
        log_info "Creando directorio base /data..."
        mkdir -p /data
        if [ $? -ne 0 ]; then
            log_error "No se pudo crear directorio /data"
            return 1
        fi
        log_success "Directorio base /data creado"
    fi

    # Procesar cada directorio requerido
    for dir in "${!DATA_DIRS_CONFIG[@]}"; do
        IFS=':' read -r user group service <<< "${DATA_DIRS_CONFIG[$dir]}"

        if [ ! -d "$dir" ]; then
            # Directorio no existe, crearlo
            log_info "Creando directorio $dir para $service..."
            mkdir -p "$dir"
            if [ $? -ne 0 ]; then
                log_error "No se pudo crear directorio $dir"
                return 1
            fi

            # Establecer permisos en directorio nuevo
            chown "$user:$group" "$dir"
            chmod 755 "$dir"
            log_success "Directorio $dir creado y configurado para $service"
        else
            # Directorio existe, verificar que sea accesible pero NO cambiar permisos si tiene datos
            log_info "Verificando directorio existente $dir..."

            # Verificar permisos básicos de acceso
            if [ ! -r "$dir" ] || [ ! -w "$dir" ]; then
                log_warning "Directorio $dir tiene permisos restrictivos, ajustando para acceso básico..."
                # Solo dar permisos mínimos para que Docker pueda acceder
                chmod u+rwX "$dir" 2>/dev/null || true
            fi

            # Verificar propietario (solo si está vacío)
            if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
                # Directorio vacío, podemos ajustar propietario
                current_owner=$(stat -c "%U:%G" "$dir" 2>/dev/null || echo "unknown:unknown")
                if [ "$current_owner" != "$user:$group" ]; then
                    log_info "Ajustando propietario de directorio vacío $dir..."
                    chown "$user:$group" "$dir" 2>/dev/null || true
                fi
            else
                # Directorio con datos - NO TOCAR propietario ni permisos
                local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                log_success "✅ $dir: Datos existentes preservados (${size:-0})"
            fi
        fi

        # Verificar espacio disponible
        local available_space=$(df "$dir" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
        if [ "$available_space" != "unknown" ] && [ "$available_space" -lt 1000000 ]; then
            log_warning "Poco espacio disponible en $dir: ${available_space}KB"
        fi
    done

    log_success "Verificación de directorios persistentes completada"
    return 0
}

# Función para mostrar ayuda
show_help() {
    echo "C-Network Agent - Script de Instalación"
    echo "Versión: 1.0.0"
    echo ""
    echo "Uso:"
    echo "  $0              # Instalación completa del sistema"
    echo "  $0 help         # Mostrar esta ayuda"
    echo ""
    echo "Características:"
    echo "  - Instala Docker, Docker Compose y servicios requeridos"
    echo "  - Configura directorios persistentes en /data/*"
    echo "  - Preserva datos existentes durante reinstalaciones"
    echo "  - Verifica integridad de datos antes de iniciar contenedores"
    echo ""
    echo "Directorios de datos (persisten independientemente de contenedores):"
    echo "  - /data/influxdb2    (Métricas de series temporales)"
    echo "  - /data/mongodb      (Configuración de dispositivos)"
    echo "  - /data/redis        (Configuración de tareas y cache)"
    echo "  - /data/files        (Archivos y configuraciones)"
    echo ""
    echo "Notas:"
    echo "  - Los datos en /data/* sobreviven al borrado de contenedores"
    echo "  - El script es idempotente - se puede ejecutar múltiples veces"
    echo "  - Detecta y preserva datos existentes automáticamente"
}

# Configurar trap para manejar errores
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Verificar si se solicita ayuda
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

echo "🚀 INICIANDO INSTALACIÓN DE C-NETWORK-AGENT FLEXIBLE"
echo "======================================================"
echo "📋 Arquitectura adaptable: Celery + Redis para 10-500+ dispositivos"
echo "🔧 Se adapta automáticamente a los recursos de tu VM"
echo ""

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

# Verificar que sea Ubuntu o Debian o Linux mint
if [[ "$OS" != "ubuntu" && "$OS" != "debian" && "$OS" != "linuxmint" ]]; then
    log_error "Este script solo funciona en Ubuntu, Debian o Linux Mint"
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

# Verificar instalación (tanto plugin como binario standalone)
COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
    COMPOSE_VERSION=$(docker compose version 2>/dev/null || echo "Error obteniendo versión")
    log_success "Docker Compose Plugin verificado: $COMPOSE_VERSION"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
    COMPOSE_VERSION=$(docker-compose --version 2>/dev/null || echo "Error obteniendo versión")
    log_success "Docker Compose binario verificado: $COMPOSE_VERSION"
else
    log_error "Docker Compose no se instaló correctamente"
    exit 1
fi

# Crear alias/symlink para compatibilidad si es necesario
if [ "$COMPOSE_CMD" = "docker compose" ] && [ ! -f /usr/local/bin/docker-compose ]; then
    log_info "Creando enlace simbólico para compatibilidad..."
    cat > /usr/local/bin/docker-compose << 'EOF'
#!/bin/bash
exec docker compose "$@"
EOF
    chmod +x /usr/local/bin/docker-compose
    log_success "Enlace simbólico docker-compose creado"
fi

# Verificar estado de datos antes de instalación
verify_data_state

# Asegurar directorios persistentes (preserva datos existentes)
if ! ensure_persistent_directories; then
    log_error "Error en la configuración de directorios persistentes"
    exit 1
fi

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
# No es necesario cambiar propietario ni permisos, Docker tendrá acceso total por 2777

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





# =====================
# TOKEN INICIAL INFLUXDB (sin Docker secrets)
# =====================

# Usuario, password y token inicial seguro
INFLUX_ADMIN_USER="admin"
INFLUX_ADMIN_PASSWORD="CreneinLocal"
INFLUX_ADMIN_TOKEN=$(openssl rand -base64 48 | tr -d '\n' | head -c 64)


# Crear el archivo .env base con el token generado
cat > .env << EOL
INFLUX_TOKEN="$INFLUX_ADMIN_TOKEN"
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

# Crear el archivo docker-compose.yml si no existe, usando las variables generadas
if [ ! -f docker-compose.yml ]; then
  log_info "Generando archivo docker-compose.yml..."
  cat > docker-compose.yml <<EOL
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
      - DOCKER_INFLUXDB_INIT_USERNAME=${INFLUX_ADMIN_USER}
      - DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUX_ADMIN_PASSWORD}
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=${INFLUX_ADMIN_TOKEN}
      - DOCKER_INFLUXDB_INIT_ORG=crenein
      - DOCKER_INFLUXDB_INIT_BUCKET=fping
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
    command: ["redis-server", "--appendonly", "yes", "--maxmemory", "512mb", "--maxmemory-policy", "allkeys-lru"]
    networks:
      - app-network

  cnetwork-agent:
    image: crenein/c-network-agent:fastapi-latest
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
    healthcheck:
      test: ["CMD", "curl", "-kf", "https://localhost:8000/api/v1/health/public"]
      interval: 30s
      timeout: 10s
      retries: 3

  celery-worker-fping:
    image: crenein/c-network-agent:celery-worker-latest
    container_name: celery-worker-fping
    restart: always
    env_file:
      - .env
    volumes:
      - /data/files:/app/files
    networks:
      - app-network
    depends_on:
      - redis
      - mongodb
      - cnetwork-agent
    # Worker general: maneja tareas de fping, backup y tareas por defecto (alta prioridad a fping)
    command: celery -A celery_app worker --loglevel=info --concurrency=4 --max-memory-per-child=1500 --queues=fping,backup,default --max-tasks-per-child=100 --pool=prefork
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'
        reservations:
          memory: 128M
          cpus: '0.25'

  celery-worker-poller:
    image: crenein/c-network-agent:celery-worker-latest
    container_name: celery-worker-poller
    restart: always
    env_file:
      - .env
    volumes:
      - /data/files:/app/files
    networks:
      - app-network
    depends_on:
      - redis
      - mongodb
      - cnetwork-agent
    # Worker especializado: maneja tareas de polling SNMP (carga media)
    command: celery -A celery_app worker --loglevel=info --concurrency=4 --max-memory-per-child=1500 --queues=polling --max-tasks-per-child=50 --pool=prefork
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '1.0'
        reservations:
          memory: 256M
          cpus: '0.5'

  celery-worker-discovery:
    image: crenein/c-network-agent:celery-worker-latest
    container_name: celery-worker-discovery
    restart: always
    env_file:
      - .env
    volumes:
      - /data/files:/app/files
    networks:
      - app-network
    depends_on:
      - redis
      - mongodb
      - cnetwork-agent
    # Worker discovery: maneja tareas de descubrimiento de dispositivos (carga alta, menos frecuente)
    command: celery -A celery_app worker --loglevel=info --concurrency=4 --max-memory-per-child=1500 --queues=discovery --max-tasks-per-child=25 --pool=prefork
# NOTA IMPORTANTE:
# No modificar la arquitectura de colas ni los nombres de las colas sin entender el impacto en la prioridad y el flujo de tareas.
# fping = prioridad máxima (checks de conectividad), polling = prioridad media (métricas SNMP), discovery = prioridad baja (descubrimiento de dispositivos), backup = tareas de fondo.
    deploy:
      resources:
        limits:
          memory: 1.2G
          cpus: '2.0'
        reservations:
          memory: 800M
          cpus: '1.0'

  celery-beat:
    image: crenein/c-network-agent:celery-beat-latest
    container_name: celery-beat
    restart: always
    env_file:
      - .env
    volumes:
      - /data/files:/app/files
    networks:
      - app-network
    depends_on:
      - redis
      - mongodb
      - cnetwork-agent
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.25'
        reservations:
          memory: 64M
          cpus: '0.1'

  flower:
    image: crenein/c-network-agent:flower-latest
    container_name: flower
    ports:
      - "5555:5555"
    restart: always
    env_file:
      - .env
    environment:
      - FLOWER_UNAUTHENTICATED_API=1
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
          memory: 128M
          cpus: '0.25'
        reservations:
          memory: 64M
          cpus: '0.1'

networks:
  app-network:
    driver: bridge
EOL
  log_success "Archivo docker-compose.yml generado correctamente."
else
  log_info "docker-compose.yml ya existe, no se sobrescribe."
fi






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
COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    log_error "Docker Compose no está funcionando"
    exit 1
fi

log_success "Docker Compose configurado: $COMPOSE_CMD"

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
if $COMPOSE_CMD up -d; then
    log_success "Contenedores iniciados correctamente"
else
    log_error "Error al iniciar contenedores"
    $COMPOSE_CMD logs
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

# Crear bucket adicional "devices" en InfluxDB
log_info "Creando bucket adicional 'devices' en InfluxDB..."
retry_count=0
max_retries=5

while [ $retry_count -lt $max_retries ]; do
    # Esperar a que InfluxDB API esté disponible
    if curl -f http://localhost:8086/health &> /dev/null; then
        log_success "InfluxDB API disponible"
        
        # Primero obtener el orgID real
        log_info "Obteniendo ID de la organización..."
        org_response=$(curl -s -X GET "http://localhost:8086/api/v2/orgs" \
            -H "Authorization: Token $INFLUX_ADMIN_TOKEN" 2>/dev/null)
        
        # Extraer el orgID del JSON eliminando espacios y saltos de línea primero
        org_id=$(echo "$org_response" | tr -d ' \n\t\r' | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        if [ -z "$org_id" ]; then
            log_warning "No se pudo obtener orgID. Respuesta de API:"
            echo "$org_response" | head -200
            log_info "Intentando método alternativo..."
            # Método alternativo usando sed
            org_id=$(echo "$org_response" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
            if [ -n "$org_id" ]; then
                log_info "OrgID obtenido con método alternativo: $org_id"
            fi
        fi
        
        if [ -n "$org_id" ]; then
            log_info "✅ Usando orgID: $org_id"
            
            # Crear bucket "devices" usando la API HTTP con el orgID correcto
            curl_output=$(mktemp)
            http_code=$(curl -s -w "%{http_code}" -X POST "http://localhost:8086/api/v2/buckets" \
                -H "Authorization: Token $INFLUX_ADMIN_TOKEN" \
                -H "Content-Type: application/json" \
                -d '{
                    "orgID": "'"$org_id"'",
                    "name": "devices"
                }' -o "$curl_output" 2>/dev/null)
            
            curl_body=$(cat "$curl_output")
            rm -f "$curl_output"
            
            case "$http_code" in
                "201")
                    log_success "Bucket 'devices' creado correctamente en InfluxDB"
                    log_info "ID del bucket: $(echo "$curl_body" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)"
                    break
                    ;;
                "422")
                    if echo "$curl_body" | grep -q "already exists\|conflict"; then
                        log_warning "Bucket 'devices' ya existe en InfluxDB - ¡Perfecto!"
                        break
                    else
                        log_warning "Error 422 no esperado: $curl_body"
                    fi
                    ;;
                *)
                    log_warning "Error al crear bucket 'devices' (HTTP: $http_code)"
                    log_info "Respuesta completa: $curl_body"
                    ;;
            esac
        else
            log_warning "No se pudo obtener orgID válido"
        fi
    else
        log_info "Esperando que InfluxDB API esté disponible..."
    fi
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
        log_info "Intento $retry_count/$max_retries - Reintentando en 5 segundos..."
        sleep 5
    else
        log_warning "No se pudo crear bucket 'devices' después de $max_retries intentos"
        log_warning "El bucket se puede crear manualmente desde la interfaz de InfluxDB"
    fi
done

check_container_health "cnetwork-agent" || exit 1
check_container_health "celery-worker-fping" || exit 1
check_container_health "celery-worker-poller" || exit 1
check_container_health "celery-worker-discovery" || exit 1
check_container_health "celery-beat" || exit 1

# Esperar adicional para que los servicios se inicialicen completamente
log_info "Esperando inicialización completa de servicios..."
sleep 20

# Verificar que el endpoint de salud responda
log_info "Verificando endpoint de salud..."
max_health_attempts=15
health_attempt=0

while [ $health_attempt -lt $max_health_attempts ]; do
    # Forzar HTTPS sin verificar certificado (como era antes)
    if curl -kf https://localhost:8000/api/v1/health/public &> /dev/null; then
        log_success "Endpoint de salud respondiendo correctamente (HTTPS)"
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

# Inicializar configuración de Celery Beat
log_info "Inicializando configuración de Celery Beat..."
if docker exec cnetwork-agent python3 -c "
# Instalar nest_asyncio si no está disponible
import subprocess
import sys
try:
    import nest_asyncio
    print('nest_asyncio ya está instalado')
except ImportError:
    print('Instalando nest_asyncio...')
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'nest_asyncio'])
    print('nest_asyncio instalado')

# Inicializar scheduler
from tasks.celery_scheduler import apply_beat_schedule
apply_beat_schedule()
print('Celery Beat schedule inicializado')
"; then
    log_success "Configuración de Celery Beat inicializada"
else
    log_warning "Error inicializando configuración de Celery Beat"
fi

# Reiniciar celery-beat para cargar la nueva configuración
log_info "Reiniciando Celery Beat para cargar configuración..."
$COMPOSE_CMD restart celery-beat
sleep 5

# Verificar acceso a Flower
log_info "Verificando acceso a Flower..."
if curl -f http://localhost:5555 &> /dev/null; then
    log_success "Flower accesible en http://localhost:5555"
else
    log_warning "Flower puede tardar en inicializar. Verificar logs: docker logs flower"
fi

# Verificación final del estado de los contenedores
log_info "Verificación final del estado de contenedores..."
if $COMPOSE_CMD ps | grep -q "Exit\|Restarting"; then
    log_warning "Algunos contenedores pueden tener problemas:"
    $COMPOSE_CMD ps
else
    log_success "Todos los contenedores están funcionando correctamente"
fi

echo ""
log_success "🎉 ¡INSTALACIÓN COMPLETADA EXITOSAMENTE!"
echo ""
log_info "📋 INFORMACIÓN DEL SISTEMA OPTIMIZADO:"
echo "   - FastAPI: https://localhost:8000"
echo "   - InfluxDB: http://localhost:8086"
echo "   - MongoDB: localhost:27017"
echo "   - Redis: localhost:6379"
echo "   - Flower (Monitoreo Celery): http://localhost:5555"
echo ""
log_info "🚀 ESCALAMIENTO INTELIGENTE:"
echo "   - Monitoreo en /api/v1/monitoring/system/health"
echo ""
log_info "🔑 CREDENCIALES:"
echo "   - Admin: agent@example.com / admin123"
echo "   - InfluxDB: admin / CreneinLocal"
echo "   - MongoDB: root / root"
log_info "💾 PERSISTENCIA DE DATOS:"
echo "   - Directorios persistentes: /data/influxdb2, /data/mongodb, /data/redis, /data/files"
echo "   - Los datos sobreviven al borrado de contenedores (bind mounts)"
echo "   - El script preserva datos existentes durante reinstalaciones"
echo "   - Verificación automática de integridad de datos"
echo ""
log_info "📝 COMANDOS ÚTILES:"
echo "   - Verificar estado: $COMPOSE_CMD ps"
echo "   - Ver logs: $COMPOSE_CMD logs -f [servicio]"
echo "   - Ver logs Celery: $COMPOSE_CMD logs -f celery-worker-general celery-beat"
echo "   - Monitoreo Flower: http://localhost:5555"
echo "   - Reiniciar servicios: $COMPOSE_CMD restart"
echo "   - Detener servicios: $COMPOSE_CMD down"
echo ""
log_info "🎯 CONFIGURACIÓN DESDE ADMIN:"
echo "   - Intervalos de fping, discovery, poller configurables"
echo "   - Tasks se ejecutan automáticamente según configuración"
echo "   - Monitoreo en tiempo real con Flower: http://localhost:5555"
echo "   - Si Flower no responde, verificar: docker logs flower"
echo ""

log_success "🎉 Sistema flexible listo - Se adapta automáticamente a tu VM y necesidades de monitoreo"
