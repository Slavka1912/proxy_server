#!/usr/bin/env bash
#
# install_squid_all_ifaces.sh
# Open HTTP proxy на всех интерфейсах, порт по умолчанию 3128
# Запуск без systemd (nohup)
#
set -euo pipefail
IFS=$'\n\t'

PORT="">${1:-3128}"
CONF="/etc/squid/squid.conf"
CACHE_DIR="/var/spool/squid"

echo "=== Squid installer (all interfaces, no systemd) ==="
echo "Proxy port: ${PORT}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Ошибка: нужен root. Запустите через sudo."
  exit 1
fi

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# 1) Установка squid (если apt есть)
if has_cmd apt; then
  echo "[1/6] Установка squid..."
  apt update -y
  DEBIAN_FRONTEND=noninteractive apt install -y squid curl unzip
else
  echo "[1/6] apt не найден — убедитесь, что squid установлен вручную."
fi

# 2) Резервная копия и запись нового конфига
...  

# Добавьте пометку для версии
# ##11.1