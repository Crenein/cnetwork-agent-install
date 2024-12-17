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
    fping

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

# Crear el archivo .env
cat <<EOL > .env
INFLUX_TOKEN=--n59y0@7iY2S3:\`y"A8=<!j,,
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
EOL

# Crear el archivo docker-compose.yml
cat <<EOL > docker-compose.yml
version: '3.8'

services:
  influxdb:
    image: influxdb:2.0
    ports:
      - "8086:8086"
    volumes:
      - influxdb_data2:/var/lib/influxdb2
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=admin
      - DOCKER_INFLUXDB_INIT_PASSWORD=CreneinLocal
      - DOCKER_INFLUXDB_INIT_ORG=crenein
      - DOCKER_INFLUXDB_INIT_BUCKET=fping
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=--n59y0@7iY2S3:\`y"A8=<!j,,

  mongodb:
    image: mongo:7.0
    container_name: mongodb
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: root
    volumes:
      - mongo-data:/data/db

  cnetwork-agent:
    image: crenein/c-network-agent:0.3.8
    container_name: cnetwork-agent
    ports:
      - "8000:8000"
    restart: always
    env_file:
      - .env

volumes:
  influxdb_data2:
  mongo-data:
EOL

# Levantar los servicios con Docker Compose
docker-compose up -d

# Ejecutar el comando en el contenedor cnetwork-agent
docker exec -it cnetwork-agent python3 populate_db.py