#!/bin/sh

# Скрипт wg-client_tiny.sh
# Автор: Spaghetti-jpg
# Дополнил: Ivan Svarkovsky [ivansvarkovsky@gmail.com]
# Лицензия: MIT License

# Цвета для вывода
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Логирование с цветом
log() { echo -e "${2}${1}${NC}" >&2; }

# Инициализация конфигурации
init_config() {
    CONFIG_DIR="config"
    IFACE="wg0"
    IPSET_NAME="unblock-list"
    IPSET_TIMEOUT=43200  # 12 часов
    COMMENT_UPDATE_INTERVAL=20
    DOMAINS_UPDATE_INTERVAL=10800  # 3 часа
    IPSET_BACKUP="true" # true/false
    IPSET_BACKUP_INTERVAL=10800    # 3 часа
    DNSMASQ_DIR="$CONFIG_DIR/Dnsmasq"
    DOMAINS_FILE="$CONFIG_DIR/domains.lst"
    CIDR_FILE="$CONFIG_DIR/CIDR.lst"
    DNSMASQ_FILE="$CONFIG_DIR/Dnsmasq/unblock.dnsmasq"
    SYSLOG_FILE="/tmp/syslog.log"
    PID_FILE="/tmp/update_ipset.pid"
    IPSET_BACKUP_FILE="$CONFIG_DIR/ipset_backup.conf"
    TMP_FILE="/tmp/wg_config_tmp.conf"
    DEFAULT_MTU=1420

    verbose=false
    for arg in "$@"; do
        case "$arg" in
            start|stop|restart|update|clean) command="$arg" ;;
            -v) verbose=true ;;
            *.conf) [ -f "$arg" ] && CONFIG_FILE="$arg" ;;
        esac
    done

    [ -z "$CONFIG_FILE" ] && CONFIG_FILE=$(find . -maxdepth 1 -name "*.conf" | sort -r | head -1)
    [ -z "$CONFIG_FILE" ] && { log "No config file found." "$RED"; exit 1; }
    [ "$verbose" = true ] && log "Using config: $CONFIG_FILE" "$GREEN"

    parse_config_file
    WG_CLIENT="${Address%/*}"
    WG_MASK="${Address#*/}"
    WG_SERVER=$(echo "$WG_CLIENT" | awk -F. '{print $1"."$2"."$3"."($4-1)}')
}

# Парсинг конфигурационного файла
parse_config_file() {
    get_value() {
        sed -n "/^\[$1\]/,/^\[/p" "$CONFIG_FILE" | 
        grep -v "^#" | grep "^[[:space:]]*$2[[:space:]]*=" | 
        sed "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//"
    }

    PrivateKey=$(get_value "Interface" "PrivateKey")
    Address=$(get_value "Interface" "Address")
    MTU=$(get_value "Interface" "MTU")
    PublicKey=$(get_value "Peer" "PublicKey")
    PresharedKey=$(get_value "Peer" "PresharedKey")
    AllowedIPs=$(get_value "Peer" "AllowedIPs")
    Endpoint=$(get_value "Peer" "Endpoint")
    PersistentKeepAlive=$(get_value "Peer" "PersistentKeepAlive")

    [ -z "$MTU" ] && MTU="$DEFAULT_MTU"
    [ -z "$Address" ] && Address="10.2.0.2/32"
    [ -z "$PersistentKeepAlive" ] && PersistentKeepAlive=10

    [ -z "$PrivateKey" ] || [ -z "$PublicKey" ] || [ -z "$AllowedIPs" ] || [ -z "$Endpoint" ] && 
        { log "Missing required config values." "$RED"; exit 1; }

    # Формируем временный файл без Address и MTU
    cat > "$TMP_FILE" << EOF
[Interface]
PrivateKey = $PrivateKey

[Peer]
PublicKey = $PublicKey
EOF
    [ -n "$PresharedKey" ] && echo "PresharedKey = $PresharedKey" >> "$TMP_FILE"
    cat >> "$TMP_FILE" << EOF
AllowedIPs = $AllowedIPs
Endpoint = $Endpoint
PersistentKeepalive = $PersistentKeepAlive
EOF

    [ "$verbose" = true ] && cat "$TMP_FILE" >&2
}

# Определение числа процессов
get_max_processes() {
    free_mem=$(free | awk '/Mem:/ {print $4}')
    [ -z "$free_mem" ] && { log "Memory detection failed, using 25" "$RED"; echo 25; return; }
    processes=$((free_mem / 1024))
    echo $(( processes < 10 ? 10 : processes > 35 ? 35 : processes ))
}

# Аналог timeout для ash
timeout_ash() {
    seconds=$1; shift
    "$@" & cmd_pid=$!
    ( sleep "$seconds"; kill -9 "$cmd_pid" 2>/dev/null ) & sleep_pid=$!
    wait "$cmd_pid" 2>/dev/null; cmd_status=$?
    kill -9 "$sleep_pid" 2>/dev/null
    return "$cmd_status"
}

wait_for_dnsmasq() {
  log "\nWaiting for dnsmasq to start..." $GREEN
  if ! pgrep dnsmasq > /dev/null 2>&1; then
    while ! pgrep dnsmasq > /dev/null 2>&1; do
      sleep 5
    done
  else
    sleep 5
  fi
}

create_ipset() {
  if ! ipset list $IPSET_NAME > /dev/null 2>&1; then
    log "Creating ipset $IPSET_NAME with timeout and comments..." $GREEN
    ipset create $IPSET_NAME hash:net comment timeout $IPSET_TIMEOUT
  fi
}

restore_ipset() {
  if [ -f "$IPSET_BACKUP_FILE" ]; then
    ipset restore -exist -f "$IPSET_BACKUP_FILE"
    log "Ipset $IPSET_NAME restored from $IPSET_BACKUP_FILE." $GREEN
  fi
}

save_ipset() {
  if [ "$IPSET_BACKUP" = "true" ]; then
    ipset save $IPSET_NAME > "$IPSET_BACKUP_FILE"
    log "\nIpset $IPSET_NAME saved to $IPSET_BACKUP_FILE.\n" $GREEN 
  fi
}

resolve_and_update_ipset() {
  log "Resolving domains and updating ipset $IPSET_NAME...\n"

  if [ ! -f "$DOMAINS_FILE" ]; then
    log "Error: File with unblockable resources $DOMAINS_FILE not found!" $RED
    exit 1
  fi

     DNSMASQ_PATH="$DNSMASQ_FILE"  # Путь к файлу Dnsmasq
    : > "$DNSMASQ_PATH"           # Очищаем файл Dnsmasq

  active_processes=0   

  resolve_domain() {
    local domain="$1"
    ADDR=$(timeout_ash 2s nslookup $domain localhost 2>/dev/null | awk '/Address [0-9]+: / {ip=$3} /Address: / {ip=$2} ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && ip != "127.0.0.1" {print ip}')

    if [ -n "$ADDR" ]; then
      for IP_HOST in $ADDR; do
        ipset -exist add $IPSET_NAME $IP_HOST timeout $IPSET_TIMEOUT comment "$domain"
      done
    fi
    printf "ipset=/%s/%s\n" "$domain" "$IPSET_NAME" >> "$DNSMASQ_PATH"
  }

    # Определяем максимальное количество параллельных процессов
    MAX_PARALLEL_PROCESSES=$(get_max_processes)

  while read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    [ "${line:0:1}" = "#" ] && continue

    resolve_domain "$line" &

    active_processes=$((active_processes + 1))

    if [ "$active_processes" -ge "$MAX_PARALLEL_PROCESSES" ]; then
      wait -n
      active_processes=$((active_processes - 1))
    fi
  done < "$DOMAINS_FILE"

  wait

  log "\nIpset $IPSET_NAME updated."
  log "Dnsmasq config file $DNSMASQ_PATH updated."
  log "Sending HUP signal to dnsmasq..."
  killall -HUP dnsmasq
}


update_ipset_from_cidr() {
  log "Adding CIDR to ipset $IPSET_NAME from $CIDR_FILE file..."

  if [ ! -f "$CIDR_FILE" ]; then
    log "Warning: CIDR file $CIDR_FILE not found!" $RED
    return
  fi

  while read -r cidr || [ -n "$cidr" ]; do
    [ -z "$cidr" ] && continue
    ipset -exist add $IPSET_NAME $cidr timeout $IPSET_TIMEOUT comment "$cidr"
  done < $CIDR_FILE

  log "Ipset $IPSET_NAME updated with CIDR ranges."
}

update_ipset_from_syslog() {
  ipset list $IPSET_NAME | grep '^ *[0-9]' | grep -v 'comment' | awk '{print $1}' | while read -r ip; do
    grep "reply .* is ${ip}" $SYSLOG_FILE | awk -v ip="${ip}" -v ipset_name="$IPSET_NAME" '
      {
        for (i=1; i<=NF; i++) {
          if ($i == "reply") {
            domain = $(i+1)
          }
          if ($NF == ip) {
            system("ipset -! add " ipset_name " " ip " comment \"" domain "\"")
          }
        }
      }'
  done
}

remove_pid() {
  local pid="$1"
  sed -i "/^${pid}$/d" $PID_FILE
}

start() {

  mkdir -p "$DNSMASQ_DIR"

  modprobe wireguard
  modprobe ip_set
  modprobe ip_set_hash_ip
  modprobe ip_set_hash_net
  modprobe ip_set_bitmap_ip
  modprobe ip_set_list_set
  modprobe xt_set

  wait_for_dnsmasq

  log "\nStarting WireGuard interface $IFACE...\n" $GREEN

  create_ipset
  restore_ipset
  resolve_and_update_ipset
  update_ipset_from_cidr

  ip link add dev $IFACE type wireguard
  ip addr add $WG_CLIENT/$WG_MASK dev $IFACE
  wg setconf $IFACE "$TMP_FILE"
  ip link set $IFACE up
  ip link set mtu $MTU dev $IFACE
  iptables -A FORWARD -i $IFACE -j ACCEPT

  echo 0 > /proc/sys/net/ipv4/conf/$IFACE/rp_filter

  iptables -I INPUT -i $IFACE -j ACCEPT
  iptables -t nat -I POSTROUTING -o $IFACE -j SNAT --to $WG_CLIENT
  iptables -A PREROUTING -t mangle -m set --match-set $IPSET_NAME dst,src -j MARK --set-mark 1
  ip rule add fwmark 1 table 1
  ip route add default dev $IFACE table 1
  ip route add $WG_SERVER/$WG_MASK dev $IFACE

  log "\nWireGuard interface $IFACE started.\n" $GREEN

  ( while true; do
      update_ipset_from_syslog
      sleep $COMMENT_UPDATE_INTERVAL &
      child_pid="$!"
      echo $child_pid >> $PID_FILE
      wait $child_pid
      remove_pid $child_pid
    done ) &

  echo "$!" >> $PID_FILE

  ( while true; do
      save_ipset
      sleep $IPSET_BACKUP_INTERVAL &
      child_pid="$!"
      echo $child_pid >> $PID_FILE
      wait $child_pid
      remove_pid $child_pid
    done ) &

  echo "$!" >> $PID_FILE 

  ( while true; do
      update &
      sleep $DOMAINS_UPDATE_INTERVAL &
      child_pid="$!"
      echo $child_pid >> $PID_FILE
      wait $child_pid
      remove_pid $child_pid
    done ) &

  echo "$!" >> $PID_FILE

  if [ "$IPSET_BACKUP" != "true" ]; then
    log "Skipping ipset backup as IPSET_BACKUP is not true." $RED
  fi
	
}

stop() {
    [ -f "$PID_FILE" ] && xargs kill < "$PID_FILE" 2>/dev/null && rm -f "$PID_FILE"
    ipset flush "$IPSET_NAME" 2>/dev/null
    ip route del default dev "$IFACE" table 1 2>/dev/null
    ip rule del fwmark 1 table 1 2>/dev/null
    iptables -t mangle -D PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark 1 2>/dev/null
    iptables -D FORWARD -i "$IFACE" -j ACCEPT 2>/dev/null
    iptables -D FORWARD -o "$IFACE" -j ACCEPT 2>/dev/null
    iptables -t nat -D POSTROUTING -o "$IFACE" -j SNAT --to "$WG_CLIENT" 2>/dev/null
    ip link set "$IFACE" down 2>/dev/null
    ip link delete dev "$IFACE" 2>/dev/null
    rm -f "$DNSMASQ_FILE" "$PID_FILE" "$IPSET_BACKUP_FILE" "$TMP_FILE" 2>/dev/null
}

update() {
  if [ -f "$PID_FILE" ]; then
    resolve_and_update_ipset >/dev/null 2>&1
    update_ipset_from_cidr >/dev/null 2>&1
  else
    resolve_and_update_ipset
    update_ipset_from_cidr
  fi
}

# Обработка команд
trap 'stop; exit 1' INT TERM
case "$1" in
    start)  shift; init_config "$@"; start ;;
    stop)   init_config "$@"; stop ;;
    restart) shift; init_config "$@"; stop; start ;;
    update) init_config "$@"; update ;;
    clean)  init_config "$@"; ipset flush "$IPSET_NAME" 2>/dev/null ;;
    -h)     echo "Usage: $0 [start|stop|restart|update|clean] [-v] [config_file]"; exit 0 ;;
    *)      log "Unknown command: $1" "$RED"; exit 1 ;;
esac
