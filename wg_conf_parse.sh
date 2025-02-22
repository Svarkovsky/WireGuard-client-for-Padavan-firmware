#!/bin/sh

# Директория с конфигурационным файлом
CONFIG_DIR="config"

# Находим имя конфигурационного файла (предполагаем, что он один)
CONFIG_FILE=$(find "$CONFIG_DIR" -maxdepth 1 -type f -name "*.conf" | head -n 1)

# Проверяем, найден ли файл
if [ -z "$CONFIG_FILE" ]; then
    echo "Конфигурационный файл не найден в директории $CONFIG_DIR."
    exit 1
fi

# Промежуточный файл
TMP_FILE="/tmp/wg_config_tmp.conf"


# Функция для извлечения значений и записи в файл
process_config() {
    # Функция для извлечения значения из конфигурационного файла
    get_value() {
        section=$1
        key=$2
        value=$(awk -v section="$section" -v key="$key" '
            BEGIN { FS = "="; OFS="=" }
            $0 ~ "\[" section "\]" { in_section = 1; next }
            $0 ~ "^\[" { in_section = 0 }
            in_section && $1 ~ "^"key"[[:space:]]*" {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1);
                if ($1 == key) {
                    print $0
                    exit
                }
            }
        ' "$CONFIG_FILE" | cut -d '=' -f 2- | sed 's/^[[:space:]]*//' | cut -d ',' -f 1)

        if [ -z "$value" ]; then
            echo "Не найдено"
        else
            echo "$value"
        fi
    }

    # Извлечение значений из секции [Interface]
    PrivateKey=$(get_value "Interface" "PrivateKey")
    MTU=$(get_value "Interface" "MTU")
    Address=$(get_value "Interface" "Address")
    DNS=$(get_value "Interface" "DNS")

    # Извлечение значений из секции [Peer]
    PublicKey=$(get_value "Peer" "PublicKey")
    AllowedIPs=$(get_value "Peer" "AllowedIPs")
    Endpoint=$(get_value "Peer" "Endpoint")
    PersistentKeepAlive=$(get_value "Peer" "PersistentKeepAlive")

    # Если PersistentKeepAlive не найден, устанавливаем значение по умолчанию 10
    if [ "$PersistentKeepAlive" = "Не найдено" ]; then
        PersistentKeepAlive=10
    fi

    # Запись в промежуточный файл
    echo "[Interface]" > "$TMP_FILE"
    echo "PrivateKey = $PrivateKey" >> "$TMP_FILE"
    echo "MTU = $MTU" >> "$TMP_FILE"
    echo "Address = $Address" >> "$TMP_FILE"
    echo "DNS = $DNS" >> "$TMP_FILE"
    echo "" >> "$TMP_FILE"
    echo "[Peer]" >> "$TMP_FILE"
    echo "PublicKey = $PublicKey" >> "$TMP_FILE"
    echo "AllowedIPs = $AllowedIPs" >> "$TMP_FILE"
    echo "Endpoint = $Endpoint" >> "$TMP_FILE"
    echo "PersistentKeepAlive = $PersistentKeepAlive" >> "$TMP_FILE"

    # Вывод значений переменных из файла
    echo "Конфигурационный файл: $CONFIG_FILE"
    while IFS= read -r line; do
        echo "$line"
    done < "$TMP_FILE"
}

# Вызываем функцию process_config
process_config











