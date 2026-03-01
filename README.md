# Nextcloud Docker Installer (Nginx + Stream + SNI)

Интерактивный bash-скрипт для установки и удаления **Nextcloud** на VPS  
с использованием **Docker**, **Nginx**, **TLS passthrough (stream)** и **Let's Encrypt**.

Проект рассчитан на **личное облако**, но легко масштабируется для семьи или небольшой команды.

---

## ✨ Возможности

- 🔐 HTTPS (Let's Encrypt, auto-renew)
- 🌐 Доступ через браузер, WebDAV, клиенты Nextcloud
- 🐳 Docker + Docker Compose
- 🔀 Nginx stream (SNI → несколько сервисов на 443)
- 📦 MariaDB
- 🔁 Чистый rollback (uninstall)
- 💾 Умная система бэкапов конфигов
- 📊 Проверка свободного места перед установкой
- 🔄 Повторный запуск install — безопасен

---

## 📋 Требования

- Ubuntu **24.04** (рекомендуется)
- Nginx (уже установлен)
- Docker + Docker Compose
- Certbot + nginx plugin
- Открытые порты:
  - 80 (certbot)
  - 443 (stream)
- Домен, указывающий на сервер

---

## 🧠 Архитектура

```text
Internet
   |
   | 443 (TLS)
   v
Nginx stream (ssl_preread + SNI)
   |
   +--> cloud.example.com → 127.0.0.1:6443
                               |
                               v
                        Nginx HTTPS (proxy)
                               |
                               v
                    Docker Nextcloud (Apache)
```
## 🚀 Установка
```bash
chmod +x install_nextcloud.sh
sudo ./install_nextcloud.sh
```
Скрипт спросит:
- домен (cloud.example.com)
- порт для Docker-контейнера (например 8888)

## 🧹 Удаление
```bash
chmod +x uninstall_nextcloud.sh
sudo ./uninstall_nextcloud.sh
```
- Контейнеры будут остановлены
- Конфигурация Nginx восстановлена из original-бэкапов
- Сертификат Let's Encrypt удаляются только по подтверждению
- Данные Nextcloud удаляются только по подтверждению

## 💾 Бэкапы конфигурации
Тип   Когда создаётся
- .original   один раз, до первых изменений
- .nextcloud  перед правками Nextcloud
**Используются для безопасного отката.**
