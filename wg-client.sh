#!/bin/sh


# Скрипт wg-client.sh
# Автор: Spaghetti-jpg
# Дополнил: Ivan Svarkovsky [ivansvarkovsky@gmail.com]
# Лицензия: MIT License
#
# Этот скрипт выпущен под лицензией MIT.
# Полный текст лицензии смотрите в файле LICENSE.



# Функция: get_script_variables
# Описание: Инициализирует основные переменные скрипта, обрабатывает аргументы командной строки,
# определяет конфигурационный файл WireGuard и задает значения по умолчанию.
# Аргументы: Все аргументы командной строки ("$@").
# Возвращает: Глобальные переменные для использования в других функциях.
get_script_variables() {
    # Устанавливаем базовый каталог для конфигурационных файлов
    CONFIG_DIR="config"

    # Локальные переменные для анализа аргументов:
    # verbose - флаг подробного вывода (-v), по умолчанию отключен
    # config_file - путь к конфигурационному файлу, если указан
    # command - команда (start, stop и т.д.), если передана
    local verbose=false
    local config_file=""
    local command=""

    # Цикл обработки аргументов:
    # Проходим по всем переданным аргументам и классифицируем их
    for arg in "$@"; do
        case "$arg" in
            start|stop|restart|update|clean)
                # Если аргумент - команда, сохраняем её
                command="$arg"
                ;;
            -v)
                # Если аргумент - флаг -v, включаем подробный вывод
                verbose=true
                ;;
            *.conf)
                # Если аргумент заканчивается на .conf и файл существует, используем его как конфигурационный
                if [ -f "$arg" ]; then
                    config_file="$arg"
                fi
                ;;
        esac
    done

    # Определяем глобальную переменную CONFIG_FILE:
    # Если config_file задан и существует, используем его
    if [ -n "$config_file" ]; then
        CONFIG_FILE="$config_file"
        # При verbose=true выводим сообщение о выбранном файле в зеленом цвете
        [ "$verbose" = true ] && log "Using specified config file: $CONFIG_FILE" "$GREEN"
    else
        # Иначе ищем самый новый .conf файл в текущем каталоге:
        # find ищет файлы с расширением .conf, сортируем по времени изменения, берем последний
        CONFIG_FILE=$(find . -maxdepth 1 -type f -name "*.conf" -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
        # Если файл не найден, выводим ошибку и завершаем скрипт
        if [ -z "$CONFIG_FILE" ]; then
            log "No config file found in current directory." "$RED"
            exit 1
        fi
        # При verbose=true сообщаем о найденном файле
        [ "$verbose" = true ] && log "Using latest found config file: $CONFIG_FILE" "$GREEN"
    fi

    # Задаем глобальные переменные со значениями по умолчанию:
    IFACE="wg0"                        # Имя WireGuard интерфейса
    IPSET_NAME="unblock-list"          # Имя IPset списка
    IPSET_TIMEOUT="43200"              # Таймаут IPset записей (в секундах, 12 часов)
    COMMENT_UPDATE_INTERVAL="20"       # Интервал обновления комментариев (секунды)
    DOMAINS_UPDATE_INTERVAL="10800"    # Интервал обновления доменов (секунды, 3 часа)
    IPSET_BACKUP_INTERVAL="10800"      # Интервал резервного копирования IPset (секунды, 3 часа)
    DOMAINS_FILE="$CONFIG_DIR/domains.lst"  # Файл со списком доменов
    CIDR_FILE="$CONFIG_DIR/CIDR.lst"        # Файл со списком CIDR
    DNSMASQ_DIR="$CONFIG_DIR/Dnsmasq"       # Каталог для конфигурации Dnsmasq
    DNSMASQ_FILE="$DNSMASQ_DIR/unblock.dnsmasq"  # Файл конфигурации Dnsmasq
    SYSLOG_FILE="/tmp/syslog.log"      # Путь к системному логу
    PID_FILE="/tmp/update_ipset.pid"   # Файл для хранения PID фоновых процессов
    IPSET_BACKUP_FILE="$CONFIG_DIR/ipset_backup.conf"  # Файл резервной копии IPset
    IPSET_BACKUP="true"                # Флаг активации резервного копирования IPset
    TMP_FILE="/tmp/wg_config_tmp.conf" # Временный файл для конфигурации WireGuard
    DEFAULT_MTU=1420                   # Значение MTU по умолчанию

    # Цветовые коды для вывода в терминале:
    GREEN='\033[1;32m'  # Яркий зеленый для успешных сообщений
    RED='\033[1;31m'    # Яркий красный для ошибок
    YELLOW='\033[1;33m' # Желтый для числовых данных
    NC='\033[0m'        # Сброс цвета

    # Вызываем функцию process_config для разбора конфигурационного файла
    process_config "$@"
    # Вычисляем клиентский IP (без маски) и маску из Address
    WG_CLIENT="${Address%/*}"  # Удаляем часть после "/"
    WG_MASK="${Address#*/}"    # Удаляем часть до "/"
    # Вычисляем IP сервера, уменьшая клиентский IP на 1
    WG_SERVER=$(decrement_ip "$WG_CLIENT")
}

# Функция: get_max_processes
# Описание: Определяет максимальное количество параллельных процессов на основе доступной памяти.
# Использует команду free для получения свободной памяти, делит её на 1 МБ на процесс,
# ограничивает результат диапазоном 10-35 для адаптации к разным устройствам.
# Возвращает: Число процессов через echo.
get_max_processes() {
    # Получаем объем свободной памяти в килобайтах из вывода free
    FREE_MEM=$(free | awk '/Mem:/ {print $4}')
    # Если память не удалось определить, используем значение по умолчанию (25)
    if [ -z "$FREE_MEM" ]; then
        log "Failed to determine available memory, defaulting to 25 processes" "$RED"
        echo "25"
        return
    fi
    # Вычисляем количество процессов: свободная память делится на 1024 КБ (1 МБ на процесс)
    MAX_PROCESSES=$((FREE_MEM / 1024))
    # Ограничиваем снизу (минимум 10 процессов)
    [ "$MAX_PROCESSES" -le 10 ] && MAX_PROCESSES=10
    # Ограничиваем сверху (максимум 35 процессов)
    [ "$MAX_PROCESSES" -ge 35 ] && MAX_PROCESSES=35
    # Возвращаем результат
    echo "$MAX_PROCESSES"
}

# Функция: decrement_ip
# Описание: Уменьшает заданный IP-адрес на 1. Используется для вычисления IP сервера.
# Например, 10.2.0.2 становится 10.2.0.1.
# Аргументы: IP-адрес в формате "x.x.x.x".
# Возвращает: Новый IP-адрес через echo.
decrement_ip() {
    local ip_address="$1"  # Сохраняем входной IP-адрес
    local o1 o2 o3 o4      # Переменные для октетов IP
    IFS=.                  # Устанавливаем разделитель как точку
    set -- $ip_address     # Разделяем IP на октеты
    o1="$1"                # Первый октет
    o2="$2"                # Второй октет
    o3="$3"                # Третий октет
    o4="$4"                # Четвертый октет
    unset IFS              # Сбрасываем разделитель
    o4=$((o4 - 1))         # Уменьшаем последний октет на 1
    # Если последний октет стал меньше 0, корректируем старшие октеты
    if [ "$o4" -lt 0 ]; then
        o4=255             # Устанавливаем 255
        o3=$((o3 - 1))     # Уменьшаем третий октет
        if [ "$o3" -lt 0 ]; then
            o3=255         # Устанавливаем 255
            o2=$((o2 - 1)) # Уменьшаем второй октет
            if [ "$o2" -lt 0 ]; then
                o2=255     # Устанавливаем 255
                o1=$((o1 - 1))  # Уменьшаем первый октет
                if [ "$o1" -lt 0 ]; then
                    o1=0   # Устанавливаем 0, если первый октет исчерпан
                fi
            fi
        fi
    fi
    # Возвращаем новый IP-адрес
    echo "$o1.$o2.$o3.$o4"
}

# Функция: process_config
# Описание: Извлекает параметры из конфигурационного файла WireGuard,
# устанавливает значения по умолчанию для отсутствующих параметров и записывает данные во временный файл.
# Аргументы: Все аргументы командной строки ("$@").
# Возвращает: Глобальные переменные с данными конфигурации.
process_config() {
    local quiet_mode=true  # По умолчанию тихий режим (без вывода)

    # Проверяем наличие флага -v для отключения тихого режима
    for arg in "$@"; do
        if [ "$arg" = "-v" ]; then
            quiet_mode=false  # Отключаем тихий режим при -v
            break
        fi
    done

    # Внутренняя функция: get_value
    # Описание: Извлекает значение ключа из указанной секции конфигурационного файла.
    # Аргументы: $1 - секция (Interface/Peer), $2 - ключ (PrivateKey, Address и т.д.).
    # Возвращает: Значение через echo или "Не найдено", если ключ отсутствует.
    get_value() {
        section="$1"  # Секция конфига (Interface или Peer)
        key="$2"      # Ключ для поиска
        value=$(awk -v section="$section" -v key="$key" '
            BEGIN { FS = "[[:space:]]*="; found_section=0 }  # Устанавливаем разделитель как "="
            $0 ~ "\\[" section "\\]" { found_section=1; next }  # Находим секцию
            $0 ~ "^\\[" && found_section { found_section=0 }  # Выходим из секции при новой
            found_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
                if ($0 ~ "^[[:space:]]*#") next  # Пропускаем закомментированные строки
                sub(/^[[:space:]]*"?"key"[[:space:]]*=+[[:space:]]*/, "")  # Удаляем ключ и пробелы
                sub(/[[:space:]]*$/, "")  # Удаляем конечные пробелы
                print $0  # Выводим значение
                exit
            }
        ' "$CONFIG_FILE")
        # Если значение не найдено, возвращаем "Не найдено"
        if [ -z "$value" ]; then
            echo "Не найдено"
        else
            echo "$value"
        fi
    }

    # Извлекаем параметры из секции Interface
    PrivateKey=$(get_value "Interface" "PrivateKey")  # Приватный ключ клиента
    MTU=$(get_value "Interface" "MTU")               # MTU интерфейса
    Address=$(get_value "Interface" "Address")       # IP-адрес клиента с маской
    DNS=$(get_value "Interface" "DNS")               # DNS-серверы (не используется в скрипте)

    # Устанавливаем значения по умолчанию, если параметры не найдены
    if [ "$MTU" = "Не найдено" ]; then
        MTU="$DEFAULT_MTU"  # MTU по умолчанию (1420)
    fi
    if [ "$Address" = "Не найдено" ]; then
        Address="10.2.0.2/32"  # IP по умолчанию для клиента
    fi

    # Извлекаем параметры из секции Peer
    PublicKey=$(get_value "Peer" "PublicKey")           # Публичный ключ сервера
    AllowedIPs=$(get_value "Peer" "AllowedIPs")         # Разрешенные IP для туннеля
    Endpoint=$(get_value "Peer" "Endpoint")             # Адрес сервера (IP:порт)
    PersistentKeepAlive=$(get_value "Peer" "PersistentKeepAlive")  # Интервал keepalive

    # Устанавливаем значение по умолчанию для PersistentKeepAlive
    if [ "$PersistentKeepAlive" = "Не найдено" ]; then
        PersistentKeepAlive=10  # 10 секунд по умолчанию
    fi

    # Проверяем наличие обязательных параметров
    if [ "$PrivateKey" = "Не найдено" ] || [ "$PublicKey" = "Не найдено" ] || \
       [ "$AllowedIPs" = "Не найдено" ] || [ "$Endpoint" = "Не найдено" ]; then
        echo "Error: Required values missing in config file."
        exit 1
    fi

    # Записываем конфигурацию во временный файл для WireGuard
    echo "[Interface]" > "$TMP_FILE"          # Секция Interface
    echo "$PrivateKey" >> "$TMP_FILE"         # Приватный ключ
    echo "" >> "$TMP_FILE"                    # Пустая строка
    echo "[Peer]" >> "$TMP_FILE"              # Секция Peer
    echo "$PublicKey" >> "$TMP_FILE"          # Публичный ключ
    echo "$AllowedIPs" >> "$TMP_FILE"         # Разрешенные IP
    echo "$Endpoint" >> "$TMP_FILE"           # Адрес сервера
    echo "$PersistentKeepAlive" >> "$TMP_FILE"  # Keepalive

    # Если тихий режим отключен (-v), выводим содержимое временного файла
    if ! "$quiet_mode"; then
        while IFS= read -r line; do
            echo "$line"
        done < "$TMP_FILE"
    fi
}

# Функция: log
# Описание: Выводит цветное сообщение в stderr.
# Аргументы: $1 - текст сообщения, $2 - цвет (GREEN, RED, YELLOW).
log() {
    local color=$2  # Цвет текста
    echo -e "${color}${1}${NC}" >&2  # Выводим сообщение с цветом и сбрасываем цвет
}

# Функция: wait_for_dnsmasq
# Описание: Ожидает запуска процесса dnsmasq, если он еще не активен.
# Если dnsmasq уже работает, делает паузу на 5 секунд.
wait_for_dnsmasq() {
    log "\nWaiting for dnsmasq to start..." "$GREEN"
    # Проверяем, запущен ли dnsmasq
    if ! pgrep dnsmasq > /dev/null 2>&1; then
        # Если нет, ждем его запуска с интервалом 5 секунд
        while ! pgrep dnsmasq > /dev/null 2>&1; do
            sleep 5
        done
    else
        # Если уже запущен, ждем 5 секунд
        sleep 5
    fi
}

# Функция: create_ipset
# Описание: Создает IPset список с именем $IPSET_NAME, если он еще не существует.
# Использует тип hash:net с поддержкой комментариев и таймаутом.
create_ipset() {
    # Проверяем наличие IPset списка
    if ! ipset list "$IPSET_NAME" > /dev/null 2>&1; then
        log "Creating ipset $IPSET_NAME with timeout and comments..." "$GREEN"
        # Создаем IPset с указанными параметрами
        ipset create "$IPSET_NAME" hash:net comment timeout "$IPSET_TIMEOUT"
    fi
}

# Функция: restore_ipset
# Описание: Восстанавливает IPset список из файла резервной копии, если он существует.
restore_ipset() {
    # Проверяем наличие файла резервной копии
    if [ -f "$IPSET_BACKUP_FILE" ]; then
        # Восстанавливаем IPset с опцией -exist (игнорируем ошибки существующих записей)
        ipset restore -exist -f "$IPSET_BACKUP_FILE"
        log "Ipset $IPSET_NAME restored from $IPSET_BACKUP_FILE." "$GREEN"
    fi
}

# Функция: save_ipset
# Описание: Сохраняет текущий IPset список в файл резервной копии, если $IPSET_BACKUP=true.
save_ipset() {
    if [ "$IPSET_BACKUP" = "true" ]; then
        # Сохраняем IPset в файл
        ipset save "$IPSET_NAME" > "$IPSET_BACKUP_FILE"
        log "\nIpset $IPSET_NAME saved to $IPSET_BACKUP_FILE.\n" "$GREEN"
    fi
}

# Функция: resolve_and_update_ipset
# Описание: Разрешает домены из $DOMAINS_FILE в IP-адреса, добавляет их в IPset список
# и обновляет конфигурацию Dnsmasq. Использует параллельную обработку с ограничением процессов.
resolve_and_update_ipset() {
    log "Resolving domains and updating ipset $IPSET_NAME...\n" "$GREEN"

    # Проверяем существование файла с доменами
    if [ ! -f "$DOMAINS_FILE" ]; then
        log "Error: Domains file $DOMAINS_FILE not found!" "$RED"
        exit 1
    fi

    DNSMASQ_PATH="$DNSMASQ_FILE"  # Путь к файлу Dnsmasq
    : > "$DNSMASQ_PATH"           # Очищаем файл Dnsmasq

    active_processes=0  # Счетчик активных фоновых процессов

    # Внутренняя функция: resolve_domain
    # Описание: Разрешает домен в IP-адрес(а) через nslookup и добавляет их в IPset.
    # Аргументы: $1 - домен для разрешения.
    resolve_domain() {
        local domain="$1"
        # Выполняем nslookup, фильтруем IP-адреса, исключаем 127.0.0.1
        ADDR=$(nslookup "$domain" localhost 2>/dev/null | awk '/Address [0-9]+: / {ip=$3} /Address: / {ip=$2} ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && ip != "127.0.0.1" {print ip}')
        # Если IP найдены, добавляем их в IPset с комментарием (доменом)
        if [ -n "$ADDR" ]; then
            for IP_HOST in $ADDR; do
                ipset -exist add "$IPSET_NAME" "$IP_HOST" timeout "$IPSET_TIMEOUT" comment "$domain"
            done
        fi
        # Добавляем правило в файл Dnsmasq
        printf "ipset=/%s/%s\n" "$domain" "$IPSET_NAME" >> "$DNSMASQ_PATH"
    }

    # Определяем максимальное количество параллельных процессов
    MAX_PARALLEL_PROCESSES=$(get_max_processes)

    # Подсчитываем общее количество доменов для прогресс-бара
    total_domains=$(wc -l < "$DOMAINS_FILE")
    processed_domains=0  # Счетчик обработанных доменов
    echo "Total domains to process: $total_domains"

    # Читаем файл доменов построчно, включая последнюю строку без \n
    while read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue  # Пропускаем пустые строки
        [ "${line:0:1}" = "#" ] && continue  # Пропускаем комментарии

        # Запускаем разрешение домена в фоновом режиме
        resolve_domain "$line" &

        active_processes=$((active_processes + 1))  # Увеличиваем счетчик процессов
        processed_domains=$((processed_domains + 1))  # Увеличиваем счетчик доменов
        # Обновляем прогресс-бар
        echo -ne "Processed domains: ${YELLOW}${processed_domains}${NC} of ${YELLOW}${total_domains}${NC} \r"

        # Если достигнут лимит процессов, ждем завершения одного
        if [ "$active_processes" -ge "$MAX_PARALLEL_PROCESSES" ]; then
            wait -n
            active_processes=$((active_processes - 1))
        fi
    done < "$DOMAINS_FILE"

    wait  # Ждем завершения всех фоновых процессов
    echo ""  # Перевод строки после прогресс-бара
    echo "Domain processing completed: $total_domains processed."

    # Финальные сообщения и перезапуск Dnsmasq
    log "\nIpset $IPSET_NAME updated." "$GREEN"
    log "Dnsmasq config file $DNSMASQ_PATH updated." "$GREEN"
    log "Sending HUP signal to dnsmasq..." "$GREEN"
    killall -HUP dnsmasq  # Перезагружаем конфигурацию Dnsmasq
}

# Функция: update_ipset_from_cidr
# Описание: Добавляет CIDR диапазоны из файла $CIDR_FILE в IPset список.
update_ipset_from_cidr() {
    log "Adding CIDR to ipset $IPSET_NAME from $CIDR_FILE file..." "$GREEN"

    # Проверяем наличие файла CIDR
    if [ ! -f "$CIDR_FILE" ]; then
        log "Warning: CIDR file $CIDR_FILE not found!" "$RED"
        return
    fi

    # Подсчитываем общее количество CIDR для прогресс-бара
    total_cidrs=$(wc -l < "$CIDR_FILE")
    processed_cidrs=0  # Счетчик обработанных записей
    echo "Total CIDR entries to process: $total_cidrs"

    # Читаем файл CIDR построчно
    while read -r cidr || [ -n "$cidr" ]; do
        [ -z "$cidr" ] && continue  # Пропускаем пустые строки
        # Добавляем CIDR в IPset с комментарием (сам CIDR)
        ipset -exist add "$IPSET_NAME" "$cidr" timeout "$IPSET_TIMEOUT" comment "$cidr"

        processed_cidrs=$((processed_cidrs + 1))  # Увеличиваем счетчик
        # Обновляем прогресс-бар
        echo -ne "Processed CIDR entries: ${YELLOW}${processed_cidrs}${NC} of ${YELLOW}${total_cidrs}${NC} \r"
    done < "$CIDR_FILE"

    wait  # Ждем завершения (хотя тут нет фоновых процессов)
    echo ""  # Перевод строки после прогресс-бара
    echo "CIDR processing completed: $total_cidrs processed."

    log "Ipset $IPSET_NAME updated with CIDR ranges." "$GREEN"
}

# Функция: update_ipset_from_syslog
# Описание: Обновляет комментарии в IPset на основе записей из системного лога ($SYSLOG_FILE).
update_ipset_from_syslog() {
    # Извлекаем IP-адреса из IPset, исключая строки с комментариями
    ipset list "$IPSET_NAME" | grep '^ *[0-9]' | grep -v 'comment' | awk '{print $1}' | while read -r ip; do
        # Ищем в логе строки вида "reply <domain> is <ip>" и добавляем комментарий
        grep "reply .* is ${ip}" "$SYSLOG_FILE" | awk -v ip="${ip}" -v ipset_name="$IPSET_NAME" '
            {
                for (i=1; i<=NF; i++) {
                    if ($i == "reply") {
                        domain = $(i+1)  # Извлекаем домен после "reply"
                    }
                    if ($NF == ip) {
                        # Добавляем IP в IPset с комментарием (доменом)
                        system("ipset -! add " ipset_name " " ip " comment \"" domain "\"")
                    }
                }
            }'
    done
}

# Функция: remove_pid
# Описание: Удаляет указанный PID из файла $PID_FILE.
# Аргументы: $1 - PID процесса.
remove_pid() {
    local pid="$1"
    # Удаляем строку с PID из файла
    sed -i "/^${pid}$/d" "$PID_FILE"
}

# Функция: help
# Описание: Выводит справку по использованию скрипта и завершает выполнение.
help() {
    echo "Usage: $(basename "$0") [start|stop|restart|update|clean] [-v] [config_file]"
    echo ""
    echo "  start             Start WireGuard interface and background processes."
    echo "  stop              Stop WireGuard interface and background processes."
    echo "  restart           Restart WireGuard interface and background processes."
    echo "  update            Update IPset list and Dnsmasq configuration."
    echo "  clean             Clean IPset list."
    echo "  -v                Enable verbose output."
    echo "  config_file       Path to WireGuard configuration file."
    echo ""
    echo "If config_file is not specified, the latest .conf file in the current directory is used."
    exit 0
}

# Функция: start
# Описание: Запускает WireGuard интерфейс, настраивает IPset, маршруты и фоновые процессы.
start() {
    # Создаем каталог для Dnsmasq, если его нет
    mkdir -p "$DNSMASQ_DIR"

    # Загружаем необходимые модули ядра для WireGuard и IPset
    modprobe wireguard
    modprobe ip_set
    modprobe ip_set_hash_ip
    modprobe ip_set_hash_net
    modprobe ip_set_bitmap_ip
    modprobe ip_set_list_set
    modprobe xt_set

    # Ждем запуска Dnsmasq
    wait_for_dnsmasq

    log "\nStarting WireGuard interface $IFACE...\n" "$GREEN"

    # Создаем и восстанавливаем IPset, обновляем его данными из доменов и CIDR
    create_ipset
    restore_ipset
    resolve_and_update_ipset
    update_ipset_from_cidr

    # Настраиваем WireGuard интерфейс
    ip link add dev "$IFACE" type wireguard         # Создаем интерфейс
    ip addr add "$WG_CLIENT/$WG_MASK" dev "$IFACE"  # Назначаем IP
    wg setconf "$IFACE" "$TMP_FILE"                 # Применяем конфигурацию
    ip link set "$IFACE" up                         # Активируем интерфейс
    ip link set mtu "$MTU" dev "$IFACE"             # Устанавливаем MTU
    iptables -A FORWARD -i "$IFACE" -j ACCEPT       # Разрешаем форвардинг

    # Отключаем reverse path filtering для интерфейса
    echo 0 > /proc/sys/net/ipv4/conf/"$IFACE"/rp_filter

    # Настраиваем правила iptables
    iptables -I INPUT -i "$IFACE" -j ACCEPT                  # Разрешаем входящий трафик
    iptables -t nat -I POSTROUTING -o "$IFACE" -j SNAT --to "$WG_CLIENT"  # NAT для исходящего трафика
    iptables -A PREROUTING -t mangle -m set --match-set "$IPSET_NAME" dst,src -j MARK --set-mark 1  # Маркируем трафик IPset

    # Настраиваем маршруты
    ip rule add fwmark 1 table 1              # Добавляем правило для маркированного трафика
    ip route add default dev "$IFACE" table 1  # Дефолтный маршрут через WireGuard
    ip route add "$WG_SERVER/$WG_MASK" dev "$IFACE"  # Маршрут к серверу

    log "\nWireGuard interface $IFACE started.\n" "$GREEN"

    # Запускаем фоновый процесс обновления комментариев из системного лога
    ( while true; do
        update_ipset_from_syslog
        sleep "$COMMENT_UPDATE_INTERVAL" &  # Спим указанный интервал
        child_pid="$!"                      # Сохраняем PID процесса sleep
        echo "$child_pid" >> "$PID_FILE"    # Записываем PID в файл
        wait "$child_pid"                   # Ждем завершения sleep
        remove_pid "$child_pid"             # Удаляем PID из файла
    done ) &
    echo "$!" >> "$PID_FILE"  # Записываем PID фонового цикла

    # Запускаем фоновый процесс сохранения IPset
    ( while true; do
        save_ipset
        sleep "$IPSET_BACKUP_INTERVAL" &
        child_pid="$!"
        echo "$child_pid" >> "$PID_FILE"
        wait "$child_pid"
        remove_pid "$child_pid"
    done ) &
    echo "$!" >> "$PID_FILE"

    # Запускаем фоновый процесс обновления доменов и CIDR
    ( while true; do
        update &
        sleep "$DOMAINS_UPDATE_INTERVAL" &
        child_pid="$!"
        echo "$child_pid" >> "$PID_FILE"
        wait "$child_pid"
        remove_pid "$child_pid"
    done ) &
    echo "$!" >> "$PID_FILE"

    # Проверяем необходимость резервного копирования IPset
    if [ "$IPSET_BACKUP" != "true" ]; then
        log "Skipping ipset backup as IPSET_BACKUP is not true." "$RED"
    fi
}

# Функция: stop
# Описание: Останавливает WireGuard интерфейс, удаляет маршруты и правила, завершает фоновые процессы.
stop() {
    log "\nStopping WireGuard interface $IFACE...\n" "$RED"

    # Завершаем все фоновые процессы, если файл PID существует
    if [ -f "$PID_FILE" ]; then
        xargs kill < "$PID_FILE"  # Убиваем процессы по PID
        rm -f "$PID_FILE"         # Удаляем файл PID
    fi

    # Очищаем IPset
    clean

    # Удаляем маршруты и правила iptables
    ip route del default dev "$IFACE" table 1
    ip rule del fwmark 1 table 1
    iptables -D PREROUTING -t mangle -m set --match-set "$IPSET_NAME" dst,src -j MARK --set-mark 1
    iptables -t nat -D POSTROUTING -o "$IFACE" -j SNAT --to "$WG_CLIENT"
    iptables -D INPUT -i "$IFACE" -j ACCEPT
    iptables -D FORWARD -i "$IFACE" -j ACCEPT
    ip link set "$IFACE" down  # Отключаем интерфейс
    ip link delete dev "$IFACE"  # Удаляем интерфейс

    log "\nWireGuard interface $IFACE stopped.\n" "$RED"
}

# Функция: update
# Описание: Обновляет IPset список данными из доменов и CIDR.
# Если фоновые процессы активны (PID файл существует), выполняется тихо.
update() {
    if [ -f "$PID_FILE" ]; then
        # Тихое обновление (вывод подавлен)
        resolve_and_update_ipset >/dev/null 2>&1
        update_ipset_from_cidr >/dev/null 2>&1
    else
        # Полное обновление с выводом
        resolve_and_update_ipset
        update_ipset_from_cidr
    fi
}

# Функция: clean
# Описание: Очищает IPset список от всех записей, если он существует.
clean() {
    log "Starting to clean ipset set: $IPSET_NAME..." "$GREEN"
    if ipset list "$IPSET_NAME" > /dev/null 2>&1; then
        ipset flush "$IPSET_NAME"  # Очищаем IPset
        log "Ipset set $IPSET_NAME cleaned." "$GREEN"
    fi
}

# Устанавливаем обработчик сигналов INT и TERM для корректного завершения
trap 'log "Script interrupted, cleaning up..."; stop; exit 1' INT TERM

# Основная логика обработки командной строки
case "$1" in
    start)
        shift  # Удаляем первый аргумент (start)
        get_script_variables "$@"  # Инициализируем переменные
        start "$@"  # Запускаем интерфейс
        ;;
    stop)
        get_script_variables "$@"  # Инициализируем переменные
        stop  # Останавливаем интерфейс
        ;;
    restart)
        shift
        get_script_variables "$@"
        stop  # Останавливаем
        start "$@"  # Запускаем заново
        ;;
    update)
        get_script_variables "$@"
        update  # Обновляем IPset
        ;;
    clean)
        get_script_variables "$@"
        clean  # Очищаем IPset
        ;;
    -h|-help)
        help  # Выводим справку
        ;;
    *)
        # Обработка неверного аргумента
        log "Unknown argument: $1" "$RED"
        log "Usage: $0 [start|stop|restart|update|clean] [-v] [config_file]" "$RED"
        log "Example: $0 start -v my_wg_config.conf" "$GREEN"
        exit 1
        ;;
esac

