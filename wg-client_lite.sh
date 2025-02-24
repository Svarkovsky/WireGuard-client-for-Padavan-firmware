#!/bin/sh

# Скрипт wg-client_lite.sh
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
    DOMAINS_UPDATE_INTERVAL=10800  # 3 часа
    IPSET_BACKUP_INTERVAL=10800    # 3 часа
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

# Ожидание dnsmasq
wait_for_dnsmasq() {
    log "Waiting for dnsmasq..." "$GREEN"
    pgrep dnsmasq >/dev/null 2>&1 || while ! pgrep dnsmasq >/dev/null 2>&1; do sleep 5; done
    sleep 5
}

# Управление IPset
manage_ipset() {
    ipset list "$IPSET_NAME" >/dev/null 2>&1 || 
        ipset create "$IPSET_NAME" hash:net comment timeout "$IPSET_TIMEOUT"
    [ -f "$IPSET_BACKUP_FILE" ] && ipset restore -exist -f "$IPSET_BACKUP_FILE"
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

# Обновление доменов в IPset
update_domains() {
    [ ! -f "$DOMAINS_FILE" ] && { log "Domains file missing: $DOMAINS_FILE" "$RED"; exit 1; }
    : > "$DNSMASQ_FILE"
    max_procs=$(get_max_processes)
    total=$(wc -l < "$DOMAINS_FILE")
    processed=0

    while read -r domain || [ -n "$domain" ]; do
        [ -z "$domain" ] || [ "${domain#\#}" != "$domain" ] && continue
        ( timeout_ash 3 nslookup "$domain" localhost 2>/dev/null | 
          awk '/Address/ {if($NF ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $NF}' | 
          grep -v "127.0.0.1" | while read -r ip; do
              ipset -exist add "$IPSET_NAME" "$ip" timeout "$IPSET_TIMEOUT" comment "$domain"
          done
          printf "ipset=/%s/%s\n" "$domain" "$IPSET_NAME" >> "$DNSMASQ_FILE"
        ) &
        processed=$((processed + 1))
        [ $((processed % max_procs)) -eq 0 ] && wait
        echo -ne "Domains: ${YELLOW}${processed}${NC}/${YELLOW}${total}${NC}\r"
    done < "$DOMAINS_FILE"
    wait
    echo
    log "Domains processed: $total" "$GREEN"
    killall -HUP dnsmasq
}

# Обновление CIDR в IPset
update_cidr() {
    [ ! -f "$CIDR_FILE" ] && { log "CIDR file missing: $CIDR_FILE (skipping)" "$YELLOW"; return; }
    total=$(wc -l < "$CIDR_FILE")
    processed=0

    while read -r cidr || [ -n "$cidr" ]; do
        [ -z "$cidr" ] || [ "${cidr#\#}" != "$cidr" ] && continue
        ipset -exist add "$IPSET_NAME" "$cidr" timeout "$IPSET_TIMEOUT" comment "$cidr"
        processed=$((processed + 1))
        echo -ne "CIDR: ${YELLOW}${processed}${NC}/${YELLOW}${total}${NC}\r"
    done < "$CIDR_FILE"
    echo
    log "CIDR processed: $total" "$GREEN"
}

# Основные команды
start() {
    mkdir -p "$(dirname "$DNSMASQ_FILE")"
    modprobe wireguard ip_set ip_set_hash_net
    wait_for_dnsmasq
    manage_ipset
    update_domains
    update_cidr

    # Сохраняем текущий дефолтный маршрут
    DEFAULT_GW=$(ip route | grep default | awk '{print $3}')
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}')

    ip link add dev "$IFACE" type wireguard
    ip addr add "$WG_CLIENT/$WG_MASK" dev "$IFACE"
    wg setconf "$IFACE" "$TMP_FILE"
    ip link set "$IFACE" up mtu "$MTU"
    
    # Маршрут к серверу через текущий шлюз
    WG_SERVER_IP=$(echo "$Endpoint" | cut -d: -f1)
    ip route add "$WG_SERVER_IP/32" via "$DEFAULT_GW" dev "$DEFAULT_IFACE"
    
    # Настройка маршрутизации только для IPset через fwmark
    ip route add default dev "$IFACE" table 1
    ip rule add fwmark 1 table 1
    iptables -t mangle -A PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark 1
    
    # Настройка iptables для NAT и форвардинга
    iptables -A FORWARD -i "$IFACE" -j ACCEPT
    iptables -A FORWARD -o "$IFACE" -j ACCEPT
    iptables -t nat -A POSTROUTING -o "$IFACE" -j SNAT --to "$WG_CLIENT"
    echo 0 > /proc/sys/net/ipv4/conf/"$IFACE"/rp_filter

    # Фоновые задачи
    ( while true; do ipset save "$IPSET_NAME" > "$IPSET_BACKUP_FILE"; sleep "$IPSET_BACKUP_INTERVAL"; done ) &
    echo "$!" >> "$PID_FILE"
    ( while true; do update_domains >/dev/null 2>&1; update_cidr >/dev/null 2>&1; sleep "$DOMAINS_UPDATE_INTERVAL"; done ) &
    echo "$!" >> "$PID_FILE"
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

# Обработка команд
trap 'stop; exit 1' INT TERM
case "$1" in
    start)  shift; init_config "$@"; start ;;
    stop)   init_config "$@"; stop ;;
    restart) shift; init_config "$@"; stop; start ;;
    update) init_config "$@"; update_domains; update_cidr ;;
    clean)  init_config "$@"; ipset flush "$IPSET_NAME" 2>/dev/null ;;
    -h)     echo "Usage: $0 [start|stop|restart|update|clean] [-v] [config_file]"; exit 0 ;;
    *)      log "Unknown command: $1" "$RED"; exit 1 ;;
esac

