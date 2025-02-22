#!/bin/sh


# Сброс всех правил iptables
iptables -F        # Очистка всех правил в текущей таблице (по умолчанию filter)
iptables -X        # Удаление всех пользовательских цепочек
iptables -Z        # Обнуление счетчиков пакетов и байтов
iptables -t nat -F  # Очистка правил в таблице nat
iptables -t nat -X  # Удаление пользовательских цепочек в таблице nat
iptables -t mangle -F  # Очистка правил в таблице mangle
iptables -t mangle -X  # Удаление пользовательских цепочек в таблице mangle
iptables -t raw -F     # Очистка правил в таблице raw
iptables -t raw -X     # Удаление пользовательских цепочек в таблице raw

# Установка политик по умолчанию (разрешить всё)
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT

echo "Все правила iptables были очищены, политики установлены в ACCEPT."