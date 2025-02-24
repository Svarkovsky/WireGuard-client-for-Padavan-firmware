# WireGuard Client for Padavan Routers with Selective VPN Routing

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**[🇬🇧 English](#english-version) | [🇺🇦 Українська](#українська-версія) | [🇨🇳 中文](#chinese-version) | [🇪🇸 Español](#spanish-version)**

---

## English Version <a name="english-version"></a>

### About

This script is a WireGuard VPN client designed for routers based on Padavan firmware. Its primary function is to provide **selective traffic routing** through a VPN connection. This allows you to configure specific websites or IP addresses to be routed through the VPN, while the rest of your traffic goes directly through your regular internet connection.

**Main Purpose of the Script:**

*   **Bypassing Geo-restrictions (Geo-blocking):** The script is primarily intended to bypass content access restrictions based on geographic location.
*   **Selective VPN:** Instead of routing all traffic through a VPN, you can selectively route only the traffic of specific sites, which can be beneficial for speed and resource efficiency.
*   **Ease of Installation and Use:** The script is designed considering the limitations of Padavan firmware and does not require installing additional packages (opkg), using dig, or a USB port.

### Key Features

*   **Automatic IPset Management:** The script uses `ipset` to create and manage a set of IP addresses that should be routed through the VPN.
*   **Dnsmasq Integration:** The script generates a configuration file for `dnsmasq` so that DNS queries for specific domains automatically route traffic through IPset.
*   **Dynamic IPset Update:** The script periodically updates the IP addresses of domains from the `domains.lst` list to keep the IPset up-to-date, even if website IP addresses change.
*   **CIDR Support:** Ability to add not only individual IP addresses but also entire CIDR ranges to the IPset from the `CIDR.lst` file.
*   **Asynchronous Domain Resolution:** Using `nslookup` in asynchronous mode to speed up processing large lists of domains.
*   **IPset Comment Restoration from Syslog:** Function to add comments to IP addresses in IPset based on data from the system log, enhancing the information in `ipset list`.
*   **IPset Backup and Restore:** Function to save and restore the IPset set upon router reboot or power failures (optional).
*   **Configuration File Selection:** Ability to specify the path to the WireGuard configuration file when running the script, or automatic use of the latest created `.conf` file.
*   **Verbose Mode:** `-v` option to enable detailed script output.

### Script Analysis

The script works as follows:

1.  **Configuration Reading:** Upon startup, the script reads settings from the WireGuard configuration file (by default, the latest `.conf` file in the directory or user-specified).
2.  **IPset Creation and Update:**
    *   The script reads the list of domains from the `config/domains.lst` file.
    *   For each domain, an asynchronous DNS query (`nslookup`) is performed to obtain IP addresses.
    *   The obtained IP addresses are added to the `unblock-list` IPset table with a timeout and comment (domain name).
    *   The `config/CIDR.lst` file is also processed, and CIDR ranges are added to IPset.
3.  **Dnsmasq Configuration:**
    *   The script creates a configuration file `unblock.dnsmasq` in the `config/Dnsmasq/` directory.
    *   Lines in the format `ipset=/domain.com/unblock-list` are added to this file for each domain from `domains.lst`. This instructs Dnsmasq to route DNS queries for these domains to IPset.
4.  **WireGuard Startup:** The script configures and starts the WireGuard interface (`wg0` by default) with parameters from the configuration file.
5.  **Routing Configuration:** The script configures routing rules (`iptables`, `ip rule`, `ip route`) to route traffic matching the `unblock-list` IPset through the WireGuard interface.
6.  **Background Processes:** Background processes are launched for:
    *   Periodic updating of comments in IPset based on data from `syslog.log`.
    *   Periodic IPset backup (optional).
    *   Periodic updating of IP addresses of domains from `domains.lst`.

**Important:** IP addresses in IPset have a timeout (default 12 hours). This is necessary to exclude routing traffic through the VPN for domains that may have changed their IP addresses.

### Authors <a name="authors-english"></a>

- **Spaghetti-jpg**: Original author.
- **Ivan Svarkovsky**: Contributor.

---

## Українська Версія <a name="українська-версія"></a>

### Про програму

Цей скрипт є WireGuard VPN клієнтом, розробленим для роутерів на базі прошивки Padavan. Його основна функція - забезпечення **селективної маршрутизації трафіку** через VPN з'єднання. Це означає, що ви можете налаштувати, щоб лише певні веб-сайти або IP-адреси направлялися через VPN, в той час як решта вашого трафіку буде йти напряму через ваше звичайне інтернет-з'єднання.

**Основне призначення скрипта:**

*   **Обхід географічних обмежень (гео-блоків):** Скрипт в першу чергу призначений для обходу блокувань доступу до контенту, що базуються на географічному положенні користувача.
*   **Селективний VPN:** Замість направлення всього трафіку через VPN, ви можете вибірково маршрутизувати тільки трафік певних сайтів, що може бути корисним для швидкості та економії ресурсів.
*   **Простота встановлення та використання:** Скрипт розроблений з урахуванням обмежень прошивки Padavan і не вимагає встановлення додаткових пакетів (opkg), використання dig, або USB-порту.

### Основні функції

*   **Автоматичне управління IPset:** Скрипт використовує `ipset` для створення та управління набором IP-адрес, які повинні маршрутизуватися через VPN.
*   **Інтеграція з Dnsmasq:** Скрипт генерує конфігураційний файл для `dnsmasq`, щоб DNS-запити для певних доменів автоматично направляли трафік через IPset.
*   **Динамічне оновлення IPset:** Скрипт періодично оновлює IP-адреси доменів зі списку `domains.lst`, щоб IPset залишався актуальним, навіть якщо IP-адреси сайтів змінюються.
*   **Підтримка CIDR:** Можливість додавання в IPset не тільки окремих IP-адрес, але й цілих CIDR-діапазонів з файлу `CIDR.lst`.
*   **Асинхронне розпізнавання доменів:** Використання `nslookup` в асинхронному режимі для прискорення обробки великих списків доменів.
*   **Відновлення коментарів IPset з Syslog:** Функція для додавання коментарів до IP-адрес в IPset на основі даних з системного журналу, що підвищує інформативність `ipset list`.
*   **Резервне копіювання та відновлення IPset:** Функція для збереження та відновлення IPset набору при перезавантаженні роутера або збоях живлення (опціонально).
*   **Вибір конфігураційного файлу:** Можливість вказати шлях до файлу конфігурації WireGuard при запуску скрипта, або автоматичне використання останнього створеного `.conf` файлу.
*   **Verbose режим:** Опція `-v` для включення детального виводу скрипта.

### Аналіз роботи скрипта

Скрипт працює наступним чином:

1.  **Читання конфігурації:** При запуску скрипт зчитує налаштування з конфігураційного файлу WireGuard (за замовчуванням останній `.conf` файл в каталозі, або вказаний користувачем).
2.  **Створення та оновлення IPset:**
    *   Скрипт читає список доменів з файлу `config/domains.lst`.
    *   Для кожного домену виконується асинхронний DNS-запит (`nslookup`) для отримання IP-адрес.
    *   Отримані IP-адреси додаються до IPset таблиці `unblock-list` з тайм-аутом та коментарем (ім'я домену).
    *   Також обробляється файл `config/CIDR.lst`, і CIDR діапазони додаються до IPset.
3.  **Конфігурація Dnsmasq:**
    *   Скрипт створює конфігураційний файл `unblock.dnsmasq` в каталозі `config/Dnsmasq/`.
    *   В цей файл додаються рядки у форматі `ipset=/domain.com/unblock-list` для кожного домену з `domains.lst`. Це вказує Dnsmasq направляти DNS-запити для цих доменів до IPset.
4.  **Запуск WireGuard:** Скрипт налаштовує та запускає WireGuard інтерфейс (`wg0` за замовчуванням) з параметрами з конфігураційного файлу.
5.  **Налаштування маршрутизації:** Скрипт налаштовує правила маршрутизації (`iptables`, `ip rule`, `ip route`) для направлення трафіку, що відповідає IPset `unblock-list`, через WireGuard інтерфейс.
6.  **Фонові процеси:** У фоновому режимі запускаються процеси для:
    *   Періодичного оновлення коментарів в IPset на основі даних з `syslog.log`.
    *   Періодичного резервного копіювання IPset (опціонально).
    *   Періодичного оновлення IP-адрес доменів з `domains.lst`.

**Важливо:** IP-адреси в IPset мають тайм-аут (за замовчуванням 12 годин). Це необхідно для того, щоб виключити маршрутизацію трафіку через VPN для доменів, які могли змінити свої IP-адреси.

### Автори <a name="authors-ukrainian"></a>

- **Spaghetti-jpg**: Оригінальний автор.
- **Ivan Svarkovsky**: Контрибутор.

---

## 中文版 <a name="chinese-version"></a>

### 关于

该脚本是一个 WireGuard VPN 客户端，专为基于 Padavan 固件的路由器设计。其主要功能是提供通过 VPN 连接的**选择性流量路由**。这允许您配置特定的网站或 IP 地址通过 VPN 路由，而其余流量则直接通过您的常规互联网连接。

**脚本的主要目的：**

*   **绕过地理限制（地理封锁）：** 该脚本主要用于绕过基于用户地理位置的内容访问限制。
*   **选择性 VPN：** 您可以选择性地仅路由特定站点的流量，而不是通过 VPN 路由所有流量，这可能有利于速度和资源效率。
*   **易于安装和使用：** 该脚本在设计时考虑了 Padavan 固件的限制，不需要安装额外的软件包 (opkg)、使用 dig 或 USB 端口。

### 主要特点

*   **自动 IPset 管理：** 该脚本使用 `ipset` 创建和管理应通过 VPN 路由的 IP 地址集。
*   **Dnsmasq 集成：** 该脚本为 `dnsmasq` 生成配置文件，以便特定域名的 DNS 查询自动通过 IPset 路由流量。
*   **动态 IPset 更新：** 该脚本定期更新 `domains.lst` 列表中域名的 IP 地址，以保持 IPset 的最新状态，即使网站 IP 地址发生更改也是如此。
*   **CIDR 支持：** 能够从 `CIDR.lst` 文件向 IPset 添加不仅是单个 IP 地址，而且是整个 CIDR 范围。
*   **异步域名解析：** 使用异步模式下的 `nslookup` 加速处理大型域名列表。
*   **从 Syslog 恢复 IPset 注释：** 根据系统日志中的数据向 IPset 中的 IP 地址添加注释的功能，增强了 `ipset list` 中的信息。
*   **IPset 备份和恢复：** 在路由器重启或电源故障时保存和恢复 IPset 集的功能（可选）。
*   **配置文件选择：** 能够在运行脚本时指定 WireGuard 配置文件的路径，或自动使用最新创建的 `.conf` 文件。
*   **详细模式：** `-v` 选项启用详细的脚本输出。

### 脚本分析

该脚本的工作方式如下：

1.  **配置读取：** 启动时，脚本从 WireGuard 配置文件（默认为目录中最新的 `.conf` 文件或用户指定的文件）读取设置。
2.  **IPset 创建和更新：**
    *   脚本从 `config/domains.lst` 文件读取域名列表。
    *   对于每个域名，执行异步 DNS 查询 (`nslookup`) 以获取 IP 地址。
    *   获得的 IP 地址将添加到带有超时和注释（域名）的 `unblock-list` IPset 表中。
    *   还会处理 `config/CIDR.lst` 文件，并将 CIDR 范围添加到 IPset。
3.  **Dnsmasq 配置：**
    *   脚本在 `config/Dnsmasq/` 目录中创建配置文件 `unblock.dnsmasq`。
    *   对于 `domains.lst` 中的每个域名，都将格式为 `ipset=/domain.com/unblock-list` 的行添加到此文件中。这指示 Dnsmasq 将这些域名的 DNS 查询路由到 IPset。
4.  **WireGuard 启动：** 脚本使用配置文件中的参数配置并启动 WireGuard 接口（默认为 `wg0`）。
5.  **路由配置：** 脚本配置路由规则 (`iptables`、`ip rule`、`ip route`)，以通过 WireGuard 接口路由与 `unblock-list` IPset 匹配的流量。
6.  **后台进程：** 启动后台进程以：
    *   根据 `syslog.log` 中的数据定期更新 IPset 中的注释。
    *   定期 IPset 备份（可选）。
    *   定期更新 `domains.lst` 中域名的 IP 地址。

**重要提示：** IPset 中的 IP 地址具有超时（默认为 12 小时）。这是为了排除通过 VPN 路由可能已更改其 IP 地址的域名的流量。

### 作者 <a name="authors-chinese"></a>

- **Spaghetti-jpg**: 原始作者。
- **Ivan Svarkovsky**: 贡献者。

---

## Español <a name="spanish-version"></a>

### Acerca de

Este script es un cliente VPN de WireGuard diseñado para enrutadores basados en firmware Padavan. Su función principal es proporcionar **enrutamiento de tráfico selectivo** a través de una conexión VPN. Esto le permite configurar sitios web o direcciones IP específicas para que se enruten a través de la VPN, mientras que el resto de su tráfico pasa directamente a través de su conexión a Internet normal.

**Propósito principal del script:**

*   **Evitar restricciones geográficas (bloqueo geográfico):** El script está destinado principalmente a evitar las restricciones de acceso a contenido basadas en la ubicación geográfica del usuario.
*   **VPN selectiva:** En lugar de enrutar todo el tráfico a través de una VPN, puede enrutar selectivamente solo el tráfico de sitios específicos, lo que puede ser beneficioso para la velocidad y la eficiencia de los recursos.
*   **Facilidad de instalación y uso:** El script está diseñado teniendo en cuenta las limitaciones del firmware Padavan y no requiere la instalación de paquetes adicionales (opkg), el uso de dig o un puerto USB.

### Características principales

*   **Gestión automática de IPset:** El script utiliza `ipset` para crear y gestionar un conjunto de direcciones IP que deben enrutarse a través de la VPN.
*   **Integración de Dnsmasq:** El script genera un archivo de configuración para `dnsmasq` de modo que las consultas DNS para dominios específicos enruten automáticamente el tráfico a través de IPset.
*   **Actualización dinámica de IPset:** El script actualiza periódicamente las direcciones IP de los dominios de la lista `domains.lst` para mantener IPset actualizado, incluso si las direcciones IP del sitio web cambian.
*   **Soporte de CIDR:** Capacidad de agregar a IPset no solo direcciones IP individuales sino también rangos CIDR completos desde el archivo `CIDR.lst`.
*   **Resolución de dominio asíncrona:** Uso de `nslookup` en modo asíncrono para acelerar el procesamiento de grandes listas de dominios.
*   **Restauración de comentarios de IPset desde Syslog:** Función para agregar comentarios a las direcciones IP en IPset basados en datos del registro del sistema, mejorando la información en `ipset list`.
*   **Copia de seguridad y restauración de IPset:** Función para guardar y restaurar el conjunto IPset tras el reinicio del enrutador o fallos de alimentación (opcional).
*   **Selección de archivo de configuración:** Capacidad de especificar la ruta al archivo de configuración de WireGuard al ejecutar el script, o uso automático del archivo `.conf` creado más recientemente.
*   **Modo Verbose:** Opción `-v` para habilitar la salida detallada del script.

### Análisis del script

El script funciona de la siguiente manera:

1.  **Lectura de configuración:** Al inicio, el script lee la configuración del archivo de configuración de WireGuard (por defecto, el archivo `.conf` más reciente en el directorio o especificado por el usuario).
2.  **Creación y actualización de IPset:**
    *   El script lee la lista de dominios del archivo `config/domains.lst`.
    *   Para cada dominio, se realiza una consulta DNS asíncrona (`nslookup`) para obtener direcciones IP.
    *   Las direcciones IP obtenidas se agregan a la tabla IPset `unblock-list` con un tiempo de espera y comentario (nombre de dominio).
    *   También se procesa el archivo `config/CIDR.lst` y los rangos CIDR se agregan a IPset.
3.  **Configuración de Dnsmasq:**
    *   El script crea un archivo de configuración `unblock.dnsmasq` en el directorio `config/Dnsmasq/`.
    *   Se agregan líneas con el formato `ipset=/domain.com/unblock-list` a este archivo para cada dominio de `domains.lst`. Esto indica a Dnsmasq que enrute las consultas DNS para estos dominios a IPset.
4.  **Inicio de WireGuard:** El script configura e inicia la interfaz WireGuard (`wg0` por defecto) con parámetros del archivo de configuración.
5.  **Configuración de enrutamiento:** El script configura reglas de enrutamiento (`iptables`, `ip rule`, `ip route`) para enrutar el tráfico que coincide con el IPset `unblock-list` a través de la interfaz WireGuard.
6.  **Procesos en segundo plano:** Se inician procesos en segundo plano para:
    *   Actualización periódica de comentarios en IPset basados en datos de `syslog.log`.
    *   Copia de seguridad periódica de IPset (opcional).
    *   Actualización periódica de direcciones IP de dominios de `domains.lst`.

**Importante:** Las direcciones IP en IPset tienen un tiempo de espera (12 horas por defecto). Esto es necesario para excluir el enrutamiento de tráfico a través de la VPN para dominios que puedan haber cambiado sus direcciones IP.

### Autores <a name="authors-spanish"></a>

- **Spaghetti-jpg**: Autor original.
- **Ivan Svarkovsky**: Colaborador.
