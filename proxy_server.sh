#!/usr/bin/env bash
#
# install_squid_all_ifaces.sh
# Open HTTP proxy на всех интерфейсах, порт по умолчанию 3128
# Запуск без systemd (nohup)
#
set -euo pipefail
IFS=$'\n\t'

PORT="${1:-3128}"
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
  DEBIAN_FRONTEND=noninteractive apt install -y squid curl unzip || true
else
  echo "[1/6] apt не найден — убедитесь, что squid установлен вручную."i

# 2) Резервная копия и запись нового конфига
echo "[2/6] Настройка конфигурации Squid (слушать на всех интерфейсах 0.0.0.0)..."
if [ -f "${CONF}" ]; then
  cp -a "${CONF}" "${CONF}.bak.$(date +%s)" || true
fi

mkdir -p "$(dirname "${CONF}")"

cat > "${CONF}" <<EOF
# Squid open forward proxy (слушает на всех интерфейсах)
http_port 0.0.0.0:${PORT}

# Logging
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log

# Memory / cache
cache_mem 256 MB
maximum_object_size_in_memory 512 KB
maximum_object_size 16 MB
cache_dir ufs ${CACHE_DIR} 1024 16 256

# OPEN proxy (все разрешено)
acl all src 0.0.0.0/0
http_access allow all

# CONNECT SSL
acl SSL_ports port 443
acl Safe_ports port 80 443
acl CONNECT method CONNECT
http_access allow CONNECT SSL_ports

# Privacy & performance
read_timeout 30 minutes
forwarded_for delete
via off
dns_v4_first on

request_body_max_size 10 MB
logfile_rotate 10
EOF

# 3) Подготовка кеша и прав
echo "[3/6] Подготовка кеша ${CACHE_DIR}..."
mkdir -p "${CACHE_DIR}"
if id proxy >/dev/null 2>&1; then
  chown -R proxy:proxy "${CACHE_DIR}" || true
fi

# 4) Sysctl tuning
echo "[4/6] Применение базового сетевого тюнинга..."
cat > /etc/sysctl.d/99-squid-tuning.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_tw_reuse = 1
EOF
sysctl --system >/dev/null || true

# 5) Инициализация кэша и запуск Squid без systemd
echo "[5/6] Инициализация кэша..."
if has_cmd squid; then
  squid -z -f "${CONF}" || true
  echo "[5b] Запуск Squid в фоне..."
  nohup squid -f "${CONF}" > /var/log/squid/nohup-squid.log 2>&1 &
  sleep 2
else
  echo "Squid не найден — установите squid вручную."i

# 6) Брандмауэр (ufw)
echo "[6/6] Настройка ufw (если есть)..."
if has_cmd ufw; then
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw allow "${PORT}/tcp"
  ufw --force enable
else
  echo "ufw не найден — пропускаем."i

# Вывод информации
SERVER_IP="$(hostname -I | awk '{print $1}' || true)"
if [ -z "${SERVER_IP}" ]; then SERVER_IP="(не удалось определить)"; fi

echo
echo "=== ГОТОВО ==="
echo "Прокси доступен на всех интерфейсах (0.0.0.0) и внешне через ваш IP (если порт открыт у хостера)."
echo "Подключение: http://${SERVER_IP}:${PORT}"
echo "Проверка с клиента:"
echo "  curl -x http://${SERVER_IP}:${PORT} http://ifconfig.co"
echo
echo "Логи squid: /var/log/squid/access.log"
echo "Для остановки:"
echo "  pkill -f '^squid'  # остановит все процессы squid"
echo
echo "Проверка порта: ss -tulpn | grep :${PORT}"