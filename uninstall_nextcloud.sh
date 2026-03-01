#!/bin/bash
set -e

### =========================
### КОНСТАНТЫ
### =========================

NC_DIR="/root/nextcloud"
NGINX_AVAIL="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
STREAM_CONF="/etc/nginx/stream-enabled/stream.conf"
HTTP_CONF="${NGINX_AVAIL}/80.conf"

### =========================
### ФУНКЦИИ
### =========================

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

restore_file() {
    local file="$1"

    if [ -f "${file}.original" ]; then
        info "Восстановление ${file} из original-бэкапа"
        mv "${file}.original" "$file"
        rm -f "${file}.nextcloud"
    else
        warn "Original-бэкап для ${file} не найден, пропуск"
    fi
}

### =========================
### ПРОВЕРКИ
### =========================

[ "$EUID" -ne 0 ] && err "Скрипт должен запускаться от root"

command -v nginx >/dev/null || err "Nginx не установлен"
command -v docker >/dev/null || err "Docker не установлен"

### =========================
### ВВОД ДАННЫХ
### =========================

read -rp "Введите домен Nextcloud для удаления (cloud.example.com): " DOMAIN
[ -z "$DOMAIN" ] && err "Домен не может быть пустым"

CLOUD_CONF="${NGINX_AVAIL}/${DOMAIN}"

### =========================
### DOCKER
### =========================

if [ -d "$NC_DIR" ]; then
    info "Остановка и удаление Docker-контейнеров Nextcloud"
    cd "$NC_DIR"
    docker compose down -v || warn "Контейнеры уже остановлены"
else
    warn "Каталог Nextcloud не найден, Docker пропущен"
fi

### =========================
### NGINX SITES
### =========================

info "Удаление nginx-конфига Nextcloud"

rm -f "${NGINX_ENABLED}/${DOMAIN}"
rm -f "$CLOUD_CONF"

### =========================
### STREAM.CONF
### =========================

info "Очистка stream.conf"

if [ -f "$STREAM_CONF.original" ]; then
    restore_file "$STREAM_CONF"
else
    warn "Original-бэкап stream.conf не найден, ручная проверка рекомендуется"
fi

### =========================
### 80.CONF
### =========================

info "Восстановление 80.conf"

if [ -f "$HTTP_CONF.original" ]; then
    restore_file "$HTTP_CONF"
else
    warn "Original-бэкап 80.conf не найден"
fi

### =========================
### CERTBOT
### =========================

if certbot certificates | grep -q "$DOMAIN"; then
    info "Найден сертификат для $DOMAIN"
    read -rp "Удалить сертификат Let's Encrypt? [y/N]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        info "Удаление сертификата Let's Encrypt для $DOMAIN"
        certbot delete --cert-name "$DOMAIN" --non-interactive
    else
        warn "Сертификат оставлен"
    fi
else
    warn "Сертификат для $DOMAIN не найден"
fi

### =========================
### NGINX
### =========================

info "Проверка конфигурации Nginx"
nginx -t

info "Перезагрузка Nginx"
systemctl reload nginx

### =========================
### ФАЙЛЫ NEXTCLOUD
### =========================

read -rp "Удалить данные Nextcloud (/root/nextcloud)? [y/N]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    info "Удаление каталога $NC_DIR"
    rm -rf "$NC_DIR"
else
    warn "Каталог Nextcloud сохранён"
fi

info "✅ Nextcloud полностью удалён и конфигурация восстановлена"