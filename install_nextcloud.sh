#!/bin/bash
set -e

### =========================
### НАСТРОЙКИ / КОНСТАНТЫ
### =========================

NC_DIR="/root/nextcloud"
NGINX_AVAIL="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
STREAM_CONF="/etc/nginx/stream-enabled/stream.conf"
HTTP_CONF="${NGINX_AVAIL}/80.conf"

NC_STREAM_PORT=6443     # ВСЕГДА 6443 для stream
NC_HTTP_PORT=""         # порт docker-контейнера (вводится пользователем)

### =========================
### ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
### =========================

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

backup_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return
    fi

    if [ ! -f "${file}.original" ]; then
        cp "$file" "${file}.original"
        info "Создан original-бэкап: ${file}.original"
    else
        cp "$file" "${file}.nextcloud"
        info "Создан nextcloud-бэкап: ${file}.nextcloud"
    fi
}

port_free() {
    ! ss -tulpen | awk '{print $5}' | grep -q ":$1$"
}

### =========================
### ПРОВЕРКИ
### =========================

[ "$EUID" -ne 0 ] && err "Скрипт должен запускаться от root"

command -v nginx >/dev/null || err "Nginx не установлен"
command -v docker >/dev/null || err "Docker не установлен"
command -v docker-compose >/dev/null || command -v docker >/dev/null || err "Docker Compose не найден"
command -v certbot >/dev/null || err "Certbot не установлен"

### =========================
### ВВОД ДАННЫХ
### =========================

read -rp "Введите домен для Nextcloud (например cloud.example.com): " DOMAIN
[ -z "$DOMAIN" ] && err "Домен не может быть пустым"

read -rp "Введите порт для docker-контейнера Nextcloud (например 8389): " NC_HTTP_PORT
[[ ! "$NC_HTTP_PORT" =~ ^[0-9]+$ ]] && err "Некорректный порт"

if ! port_free "$NC_HTTP_PORT"; then
    err "Порт $NC_HTTP_PORT уже занят"
fi

### =========================
### ПРОВЕРКА: УЖЕ УСТАНОВЛЕНО?
### =========================

if [ -d "$NC_DIR" ] && docker ps | grep -q nextcloud; then
    warn "Nextcloud уже установлен. Никаких действий не требуется."
    exit 0
fi

### =========================
### CERTBOT
### =========================

info "Выпуск сертификата для $DOMAIN"
backup_file "$HTTP_CONF"

certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@"$DOMAIN"

### =========================
### 80.conf
### =========================

info "Обновление 80.conf"
sed -i "s/server_name .*/server_name ${DOMAIN};/" "$HTTP_CONF"

### =========================
### cloud.domain.conf
### =========================

info "Создание nginx-конфига для $DOMAIN"

CLOUD_CONF="${NGINX_AVAIL}/${DOMAIN}"
backup_file "$CLOUD_CONF"

cat > "$CLOUD_CONF" <<EOF
server {
    server_name ${DOMAIN};

    listen ${NC_STREAM_PORT} ssl http2 proxy_protocol;
    listen [::]:${NC_STREAM_PORT} ssl http2 proxy_protocol;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    client_max_body_size 10G;
    proxy_buffering off;

    location / {
        proxy_pass http://127.0.0.1:${NC_HTTP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf "$CLOUD_CONF" "${NGINX_ENABLED}/${DOMAIN}"

### =========================
### stream.conf
### =========================

info "Обновление stream.conf"
backup_file "$STREAM_CONF"

# map — перед default
if ! grep -q "${DOMAIN}" "$STREAM_CONF"; then
    sed -i "/^\s*default\s\+/i\    ${DOMAIN}   cloud;" "$STREAM_CONF"
fi

# upstream cloud — перед server {
if ! grep -q "upstream cloud" "$STREAM_CONF"; then
    sed -i "/^\s*server\s*{/i\
upstream cloud {\n\
    server 127.0.0.1:${NC_STREAM_PORT};\n\
}\n" "$STREAM_CONF"
fi

### =========================
### DOCKER COMPOSE
### =========================

info "Разворачивание Nextcloud через Docker Compose"

mkdir -p "$NC_DIR"
cd "$NC_DIR"

DB_ROOT_PASS=$(openssl rand -hex 16)
DB_PASS=$(openssl rand -hex 16)

cat > docker-compose.yml <<EOF
version: '3.8'

services:
  db:
    image: mariadb:11
    restart: always
    command: --transaction-isolation=READ-COMMITTED
    volumes:
      - ./db:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASS}
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: ${DB_PASS}

  app:
    image: nextcloud:apache
    restart: always
    ports:
      - "127.0.0.1:${NC_HTTP_PORT}:80"
    volumes:
      - ./html:/var/www/html
    environment:
      MYSQL_HOST: db
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: ${DB_PASS}
    depends_on:
      - db
EOF

docker compose up -d

### =========================
### ПРОВЕРКА И ПЕРЕЗАГРУЗКА
### =========================

info "Проверка конфигурации Nginx"
nginx -t

info "Перезагрузка Nginx"
systemctl reload nginx

info "✅ Установка Nextcloud завершена успешно!"
info "🌐 Доступ: https://${DOMAIN}"