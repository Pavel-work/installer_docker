#!/bin/bash

# ==========================================
# Docker Installer - ИСПРАВЛЕННАЯ ВЕРСИЯ
# ==========================================

# Проверка root прав
if [ "$EUID" -ne 0 ]; then 
    echo "Ошибка: запустите скрипт от root (sudo ./script.sh)"
    exit 1
fi

# Проверка dialog
if ! command -v dialog &> /dev/null; then
    echo "Установка dialog..."
    apt-get update && apt-get install -y dialog
fi

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Пути
INSTALL_DIR="/opt/docker"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
CREDENTIALS_FILE="$INSTALL_DIR/credentials.txt"
LOG_FILE="$INSTALL_DIR/install.log"

# Создание директории
mkdir -p "$INSTALL_DIR"
> "$LOG_FILE"

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Проверка порта
check_port() {
    local port=$1
    if ss -tlnp | grep -q ":${port} "; then
        return 1  # Порт занят
    fi
    return 0  # Порт свободен
}

clear

# ==========================================
# 1. Приветствие
# ==========================================
dialog --backtitle "Docker Installer v2.0" \
       --title "Добро пожаловать" \
       --yes-label "Начать" --no-label "Выход" \
       --yesno "Добро пожаловать в установщик Docker!\n\nБудут установлены Docker Engine и выбранные сервисы.\n\nТребуется: sudo, интернет, свободные порты." 12 70

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 2. Выбор сервисов
# ==========================================
choices=$(dialog --stdout \
                 --backtitle "Docker Installer" \
                 --title "Выбор сервисов" \
                 --ok-label "Установить" --cancel-label "Отмена" \
                 --checklist "Отметьте сервисы (пробел - выбор):" 18 80 8 \
                 "PostgreSQL" "База данных PostgreSQL" OFF \
                 "Qdrant" "Векторная база Qdrant" OFF \
                 "Ollama" "Локальная LLM Ollama" OFF \
                 "Apache" "Веб-сервер Apache" OFF \
                 "NginxProxy" "Nginx Proxy Manager" OFF \
                 "Portainer" "Управление Docker" OFF \
                 "n8n" "Автоматизация n8n" OFF)

[ $? -ne 0 ] && { dialog --msgbox "Отменено" 6 50; clear; exit 0; }
[ -z "$choices" ] && { dialog --msgbox "Выберите хотя бы один сервис!" 6 50; clear; exit 1; }

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')
num_selected=$(echo "$clean_choices" | wc -l)

# ==========================================
# 3. Проверка портов
# ==========================================
port_conflicts=""
declare -A service_ports=(
    ["PostgreSQL"]="5432"
    ["Qdrant"]="6333,6334"
    ["Ollama"]="11434"
    ["Apache"]="80,443"
    ["NginxProxy"]="80,81,443"
    ["Portainer"]="9000,9443"
    ["n8n"]="5678"
)

for service in $clean_choices; do
    if [ -n "${service_ports[$service]}" ]; then
        IFS=',' read -ra ports <<< "${service_ports[$service]}"
        for port in "${ports[@]}"; do
            if ! check_port $port; then
                port_conflicts="${port_conflicts}\n  • $service - порт $port ЗАНЯТ"
            fi
        done
    fi
done

if [ -n "$port_conflicts" ]; then
    dialog --title "⚠️ КОНФЛИКТ ПОРТОВ" \
           --msgbox "Следующие порты уже используются:\n${port_conflicts}\n\nОсвободите порты или выберите другие сервисы." 15 70
    clear
    exit 1
fi

# ==========================================
# 4. Подтверждение
# ==========================================
services_list=$(echo "$clean_choices" | sed 's/^/    • /')

dialog --title "Подтверждение" \
       --yes-label "Установить" --no-label "Отмена" \
       --yesno "Будут установлены:\n\n  1. Docker Engine\n  2. Docker Compose\n  3. Сервисы (${num_selected} шт.):\n\n${services_list}\n\nПродолжить?" 16 70

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# ФУНКЦИИ УСТАНОВКИ
# ==========================================

# Определение команды Docker Compose
detect_compose() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo ""
    fi
}

COMPOSE_CMD=$(detect_compose)

# Установка Docker
install_docker() {
    log "Проверка Docker..."
    
    if ! command -v docker &> /dev/null; then
        log "Установка Docker Engine..."
        dialog --infobox "\n📦 Установка Docker Engine...\n" 6 60
        
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>> "$LOG_FILE"
        sh /tmp/get-docker.sh 2>> "$LOG_FILE"
        rm -f /tmp/get-docker.sh
        
        systemctl enable docker 2>> "$LOG_FILE"
        systemctl start docker 2>> "$LOG_FILE"
        
        log "✓ Docker Engine установлен"
    else
        log "Docker уже установлен"
    fi
    
    # Установка Docker Compose если нужно
    if [ -z "$COMPOSE_CMD" ]; then
        log "Установка Docker Compose..."
        dialog --infobox "\n📦 Установка Docker Compose...\n" 6 60
        
        DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
        curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose 2>> "$LOG_FILE"
        chmod +x /usr/local/bin/docker-compose
        
        COMPOSE_CMD="docker-compose"
        log "✓ Docker Compose установлен"
    fi
    
    echo -e "${GREEN}✓ Docker готов${NC}"
    sleep 1
}

# Генерация docker-compose.yml
generate_compose() {
    cat > "$COMPOSE_FILE" << 'EOF'
version: '3.8'

services:
EOF
    log "Создан docker-compose.yml"
}

# Установка PostgreSQL
install_postgresql() {
    POSTGRES_PASSWORD=$(openssl rand -base64 16)
    
    cat >> "$COMPOSE_FILE" << EOF

  postgresql:
    image: postgres:15-alpine
    container_name: postgresql
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: postgres
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - app_network

EOF
    
    echo "PostgreSQL:
  Порт: 5432
  Пользователь: postgres
  Пароль: $POSTGRES_PASSWORD
  URL: localhost:5432" >> "$CREDENTIALS_FILE"
    
    log "✓ PostgreSQL добавлен в compose"
}

# Установка Qdrant
install_qdrant() {
    cat >> "$COMPOSE_FILE" << 'EOF'

  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    ports:
      - "6333:6333"
      - "6334:6334"
    volumes:
      - qdrant_data:/qdrant/storage
    networks:
      - app_network

EOF
    
    echo "Qdrant:
  REST API: http://localhost:6333
  gRPC: localhost:6334
  Dashboard: http://localhost:6333/dashboard" >> "$CREDENTIALS_FILE"
    
    log "✓ Qdrant добавлен в compose"
}

# Установка Ollama
install_ollama() {
    cat >> "$COMPOSE_FILE" << 'EOF'

  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    networks:
      - app_network

EOF
    
    echo "Ollama:
  Порт: 11434
  API: http://localhost:11434
  Команда: ollama pull llama2" >> "$CREDENTIALS_FILE"
    
    log "✓ Ollama добавлен в compose"
}

# Установка Apache
install_apache() {
    mkdir -p "$INSTALL_DIR/apache/html"
    echo "<h1>Apache работает!</h1>" > "$INSTALL_DIR/apache/html/index.html"
    
    cat >> "$COMPOSE_FILE" << 'EOF'

  apache:
    image: httpd:2.4-alpine
    container_name: apache
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./apache/html:/usr/local/apache2/htdocs
    networks:
      - app_network

EOF
    
    echo "Apache:
  HTTP: http://localhost:80
  HTTPS: https://localhost:443
  Директория: $INSTALL_DIR/apache/html" >> "$CREDENTIALS_FILE"
    
    log "✓ Apache добавлен в compose"
}

# Установка Nginx Proxy Manager
install_nginxproxy() {
    NGINX_PASSWORD=$(openssl rand -base64 12)
    mkdir -p "$INSTALL_DIR/nginx-proxy/data"
    mkdir -p "$INSTALL_DIR/nginx-proxy/letsencrypt"
    
    cat >> "$COMPOSE_FILE" << EOF

  nginx-proxy:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    environment:
      DB_MYSQL_HOST: npm-db
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: npm
      DB_MYSQL_PASSWORD: '${NGINX_PASSWORD}'
      DB_MYSQL_NAME: npm
    volumes:
      - ./nginx-proxy/data:/data
      - ./nginx-proxy/letsencrypt:/etc/letsencrypt
    networks:
      - app_network
    depends_on:
      - npm-db

  npm-db:
    image: 'jc21/mariadb-aria:latest'
    container_name: npm-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: '${NGINX_PASSWORD}'
      MYSQL_DATABASE: npm
      MYSQL_USER: npm
      MYSQL_PASSWORD: '${NGINX_PASSWORD}'
    volumes:
      - npm_mysql_data:/var/lib/mysql
    networks:
      - app_network

EOF
    
    echo "Nginx Proxy Manager:
  Панель: http://localhost:81
  Email: admin@example.com
  Пароль: changeme (измените при первом входе)" >> "$CREDENTIALS_FILE"
    
    log "✓ Nginx Proxy Manager добавлен в compose"
}

# Установка Portainer
install_portainer() {
    cat >> "$COMPOSE_FILE" << 'EOF'

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - app_network

EOF
    
    echo "Portainer:
  HTTP: http://localhost:9000
  HTTPS: https://localhost:9443
  Создайте admin при первом входе" >> "$CREDENTIALS_FILE"
    
    log "✓ Portainer добавлен в compose"
}

# Установка n8n
install_n8n() {
    N8N_PASSWORD=$(openssl rand -base64 12)
    
    cat >> "$COMPOSE_FILE" << EOF

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - WEBHOOK_URL=http://localhost:5678/
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - app_network

EOF
    
    echo "n8n:
  Порт: 5678
  URL: http://localhost:5678
  Логин: admin
  Пароль: $N8N_PASSWORD" >> "$CREDENTIALS_FILE"
    
    log "✓ n8n добавлен в compose"
}

# ==========================================
# ОСНОВНАЯ УСТАНОВКА
# ==========================================

log "=== НАЧАЛО УСТАНОВКИ ==="

# Инициализация
> "$CREDENTIALS_FILE"
generate_compose

# Установка Docker
install_docker

# Генерация compose для каждого сервиса
for service in $clean_choices; do
    log "Обработка сервиса: $service"
    case "$service" in
        PostgreSQL)   install_postgresql ;;
        Qdrant)       install_qdrant ;;
        Ollama)       install_ollama ;;
        Apache)       install_apache ;;
        NginxProxy)   install_nginxproxy ;;
        Portainer)    install_portainer ;;
        n8n)          install_n8n ;;
    esac
done

# Добавление сетей и volumes
cat >> "$COMPOSE_FILE" << 'EOF'

volumes:
  postgres_data:
  qdrant_data:
  ollama_data:
  portainer_data:
  n8n_data:
  npm_mysql_data:

networks:
  app_network:
    driver: bridge
EOF

log "docker-compose.yml сгенерирован"

# Запуск контейнеров
dialog --infobox "\n🚀 Запуск контейнеров...\nЭто может занять несколько минут.\nСледите за прогрессом в логах.\n" 8 60

cd "$INSTALL_DIR"

log "Запуск docker-compose up -d..."

if $COMPOSE_CMD up -d 2>> "$LOG_FILE"; then
    log "✓ Все контейнеры запущены"
    
    # Проверка статуса
    sleep 5
    $COMPOSE_CMD ps >> "$LOG_FILE" 2>&1
    
    # Чтение данных
    service_info=$(cat "$CREDENTIALS_FILE")
    
    dialog --title "✓ УСТАНОВКА ЗАВЕРШЕНА" \
           --msgbox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   ✓ ВСЕ СЕРВИСЫ УСТАНОВЛЕНЫ!\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nУстановлено: ${num_selected} сервисов\n\nДанные сохранены в:\n$CREDENTIALS_FILE\n\n${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n⚠️  СОХРАНИТЕ ЭТИ ДАННЫЕ!  ⚠️\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" 30 80
    
    # Вывод в терминал
    clear
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║           ✓  УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!  ✓            ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "Установлено сервисов: ${num_selected}"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "                    ДАННЫЕ ДОСТУПА:"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    cat "$CREDENTIALS_FILE"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Файл с данными: $CREDENTIALS_FILE"
    echo "  Docker Compose: $COMPOSE_FILE"
    echo "  Логи установки: $LOG_FILE"
    echo "  ⚠️  Сохраните эти данные!"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo -e "${GREEN}✓ Все сервисы запущены!${NC}"
    echo ""
    echo "Управление:"
    echo "  cd $INSTALL_DIR"
    echo "  $COMPOSE_CMD ps          - статус контейнеров"
    echo "  $COMPOSE_CMD logs        - логи"
    echo "  $COMPOSE_CMD down        - остановка"
    echo ""
else
    log "✗ ОШИБКА при запуске контейнеров"
    
    dialog --title "✗ ОШИБКА" \
           --msgbox "Ошибка при запуске контейнеров!\n\nПроверьте:\n  1. Интернет соединение\n  2. Свободное место на диске\n  3. Логи: $LOG_FILE\n\nКоманды для диагностики:\n  cd $INSTALL_DIR\n  $COMPOSE_CMD logs" 15 70
    
    clear
    echo -e "${RED}✗ Установка завершена с ошибкой${NC}"
    echo ""
    echo "Логи установки: $LOG_FILE"
    echo ""
    echo "Последние ошибки:"
    tail -20 "$LOG_FILE"
    echo ""
    exit 1
fi
