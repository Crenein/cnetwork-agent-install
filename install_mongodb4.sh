#!/bin/bash

# Actualizar el sistema
apt-get update -y

# Instalar paquetes necesarios
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    fping \
    vsftpd \
    tftpd-hpa

# Añadir la clave GPG oficial de Docker
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Añadir el repositorio de Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Actualizar el sistema nuevamente
apt-get update -y

# Instalar Docker
apt-get install -y docker-ce docker-ce-cli containerd.io

# Instalar Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Crear directorios para volúmenes persistentes
mkdir -p /data/influxdb2
mkdir -p /data/mongodb
mkdir -p /data/files
mkdir -p /data/redis

# Establecer permisos
chown -R 1000:1000 /data/influxdb2
chown -R 1000:1000 /data/mongodb
chown -R 1000:1000 /data/files

# Configurar FTP (vsftpd)
# Descargar archivo de configuración del repositorio
wget https://raw.githubusercontent.com/Crenein/cnetwork-agent-install/master/vsftpd.conf -O vsftpd.conf
# Eliminar archivo viejo de configuración
rm -f /etc/vsftpd.conf
# Mover el archivo de configuración descargado
mv vsftpd.conf /etc/
# Reiniciar servicio vsftpd
systemctl restart vsftpd
# Crear usuario para backups y establecer permisos
useradd -M -d /data/files backups
chown backups:backups -R /data/files
chmod 777 -R /data/files

# Configurar TFTP (tftpd-hpa)
# Descargar archivo de configuración del repositorio
wget https://raw.githubusercontent.com/Crenein/cnetwork-agent-install/master/tftpd-hpa -O tftpd-hpa
# Eliminar archivo de configuración existente
rm -f /etc/default/tftpd-hpa
# Mover el archivo de configuración descargado
mv tftpd-hpa /etc/default/
# Reiniciar servicio tftpd-hpa
systemctl restart tftpd-hpa

# Crear el archivo .env
cat > .env << 'EOL'
INFLUX_TOKEN="--n59y0@7iY2S3:y\"A8=<!j,,"
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
      - "DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=--n59y0@7iY2S3:y\"A8=<!j,,"
    networks:
      - app-network

  mongodb:
    image: mongo:4.4.6
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
    command: ["redis-server", "--appendonly", "yes"]
    networks:
      - app-network

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
    command: ["dramatiq", "workers"]

networks:
  app-network:
    driver: bridge
EOL

# Asegurarse de que Docker esté iniciado
systemctl start docker

# Esperar a que Docker esté completamente iniciado
sleep 5

# Crear y arrancar los contenedores
docker compose up -d

# Esperar a que los contenedores estén listos
echo "Esperando a que los servicios estén listos..."
sleep 20

# Ejecutar el comando en el contenedor cnetwork-agent
docker exec cnetwork-agent python3 populate_db.py
