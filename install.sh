#!/bin/bash

# ==========================================
# Docker Installer с реальным бэкендом
# ==========================================

set -e  # Остановка при ошибке

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

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Пути
INSTALL_DIR="/opt/docker"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
ENV_FILE="$INSTALL_DIR/.env"
CREDENTIALS_FILE="$INSTALL_DIR/credentials.txt"

# Создание директории
mkdir -p "$INSTALL_DIR"

clear

# ==========================================
# 1. Приветствие
# ==========================================
dialog --backtitle "Docker Installer" \
       --title "Добро пожаловать" \
       --yes-label "Начать" --no-label "Выход" \
       --yesno "Добро пожаловать в установщик Docker!\n\nБудут установлены Docker Engine и выбранные сервисы." 10 70

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
                 "Supabase" "Supabase Full Stack" OFF \
                 "n8n" "Автоматизация n8n" OFF)

[ $? -ne 0 ] && { dialog --msgbox "Отменено" 6 50; clear; exit 0; }
[ -z "$choices" ] && { dialog --msgbox "Выберите хотя бы один сервис!" 6 50; clear; exit 1; }

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')
num_selected=$(echo "$clean_choices" | wc -l)

# ==========================================
# 3. Подтверждение
# ==========================================
services_list=$(echo "$clean_choices" | sed 's/^/    • /')

dialog --title "Подтверждение" \
       --yes-label "Установить" --no-label "Отмена" \
       --yesno "Будут установлены:\n\n  1. Docker Engine\n  2. Docker Compose\n  3. Сервисы (${num_selected} шт.):\n\n${services_list}\n\nПродолжить?" 16 70

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# ФУНКЦИИ УСТАНОВКИ
# ==========================================

# Установка Docker
install_docker() {
    dialog --infobox "\n📦 Установка Docker Engine...\n" 6 60
    
    if ! command -v docker &> /dev/null; then
        # Установка Docker
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        
        # Добавление в группу docker
        usermod -aG docker $SUDO_USER 2>/dev/null || true
        
        # Запуск служб
        systemctl enable docker
        systemctl start docker
    fi
    
    # Установка Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    
    echo -e "${GREEN}✓ Docker установлен${NC}"
}

# Генерация docker-compose.yml
generate_compose() {
    cat > "$COMPOSE_FILE" << 'EOF'
version: '3.8'
services:
EOF
}

# Добавление сервиса в compose
add_service() {
    echo -e "$1" >> "$COMPOSE_FILE"
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
      - docker_network

EOF
    
    echo "PostgreSQL:
  Порт: 5432
  Пользователь: postgres
  Пароль: $POSTGRES_PASSWORD
  URL: localhost:5432" >> "$CREDENTIALS_FILE"
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
      - docker_network

EOF
    
    echo "Qdrant:
  REST API: http://localhost:6333
  gRPC: localhost:6334
  Dashboard: http://localhost:6333/dashboard" >> "$CREDENTIALS_FILE"
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
      - docker_network

EOF
    
    echo "Ollama:
  Порт: 11434
  API: http://localhost:11434
  Команда: ollama pull llama2" >> "$CREDENTIALS_FILE"
}

# Установка Apache
install_apache() {
    mkdir -p "$INSTALL_DIR/apache/html"
    
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
      - docker_network

EOF
    
    echo "Apache:
  HTTP: http://localhost:80
  HTTPS: https://localhost:443
  Директория: $INSTALL_DIR/apache/html" >> "$CREDENTIALS_FILE"
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
      DB_MYSQL_HOST: db
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: npm
      DB_MYSQL_PASSWORD: ${NGINX_PASSWORD}
      DB_MYSQL_NAME: npm
    volumes:
      - ./nginx-proxy/data:/data
      - ./nginx-proxy/letsencrypt:/etc/letsencrypt
    networks:
      - docker_network
    depends_on:
      - npm-db

  npm-db:
    image: 'jc21/mariadb-aria:latest'
    container_name: npm-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${NGINX_PASSWORD}
      MYSQL_DATABASE: npm
      MYSQL_USER: npm
      MYSQL_PASSWORD: ${NGINX_PASSWORD}
    volumes:
      - npm_mysql_data:/var/lib/mysql
    networks:
      - docker_network

EOF
    
    echo "Nginx Proxy Manager:
  Панель: http://localhost:81
  Email: admin@example.com
  Пароль: changeme (измените при первом входе)" >> "$CREDENTIALS_FILE"
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
      - docker_network

EOF
    
    echo "Portainer:
  HTTP: http://localhost:9000
  HTTPS: https://localhost:9443
  Создайте admin при первом входе" >> "$CREDENTIALS_FILE"
}

# Установка Supabase
install_supabase() {
    SUPABASE_PASSWORD=$(openssl rand -base64 16)
    
    dialog --infobox "\n📦 Supabase требует больше ресурсов...\n  Минимум: 2GB RAM, 2 CPU\n" 8 60
    sleep 2
    
    cat >> "$COMPOSE_FILE" << EOF

  supabase-kong:
    image: kong:2.8.1
    container_name: supabase-kong
    restart: unless-stopped
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /var/lib/kong/kong.yml
      KONG_DNS_ORDER: LAST,A,CNAME
      KONG_PLUGINS: request-transformer,cors,key-auth,acl,basic-auth
      KONG_NGINX_PROXY_PROXY_BUFFER_SIZE: 160k
      KONG_NGINX_PROXY_PROXY_BUFFERS: 64 160k
    ports:
      - "8000:8000"
    networks:
      - docker_network

  supabase-studio:
    image: supabase/studio:latest
    container_name: supabase-studio
    restart: unless-stopped
    environment:
      STUDIO_PG_META_URL: http://supabase-meta:8080
      POSTGRES_PASSWORD: ${SUPABASE_PASSWORD}
      DEFAULT_ORGANIZATION_NAME: Default Org
      DEFAULT_PROJECT_NAME: Default Project
    ports:
      - "8001:3000"
    networks:
      - docker_network

  supabase-auth:
    image: supabase/gotrue:latest
    container_name: supabase-auth
    restart: unless-stopped
    environment:
      GOTRUE_JWT_SECRET: ${SUPABASE_PASSWORD}
      GOTRUE_DB_DRIVER: postgres
      DB_NAMESPACE: auth
      API_EXTERNAL_URL: http://localhost:9999
    ports:
      - "9999:9999"
    networks:
      - docker_network

  supabase-meta:
    image: supabase/postgres-meta:latest
    container_name: supabase-meta
    restart: unless-stopped
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: supabase-db
      PG_META_DB_PORT: 5432
      PG_META_DB_NAME: postgres
      PG_META_DB_USER: postgres
      PG_META_DB_PASSWORD: ${SUPABASE_PASSWORD}
    networks:
      - docker_network

  supabase-db:
    image: supabase/postgres:15.1.0.117
    container_name: supabase-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${SUPABASE_PASSWORD}
      POSTGRES_DB: postgres
    ports:
      - "54322:5432"
    volumes:
      - supabase_db_data:/var/lib/postgresql/data
    networks:
      - docker_network

EOF
    
    echo "Supabase:
  Kong API: http://localhost:8000
  Studio: http://localhost:8001
  Auth: http://localhost:9999
  Postgres: localhost:54322
  Пароль: $SUPABASE_PASSWORD" >> "$CREDENTIALS_FILE"
}

# Установка n8n
install_n8n() {
    cat >> "$COMPOSE_FILE" << 'EOF'

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=admin
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - docker_network

EOF
    
    echo "n8n:
  Порт: 5678
  URL: http://localhost:5678
  Логин: admin
  Пароль: admin (измените!)" >> "$CREDENTIALS_FILE"
}

# ==========================================
# ОСНОВНАЯ УСТАНОВКА
# ==========================================

# Инициализация
> "$CREDENTIALS_FILE"
generate_compose

# Установка Docker
install_docker

# Генерация compose для каждого сервиса
for service in $clean_choices; do
    case "$service" in
        PostgreSQL)   install_postgresql ;;
        Qdrant)       install_qdrant ;;
        Ollama)       install_ollama ;;
        Apache)       install_apache ;;
        NginxProxy)   install_nginxproxy ;;
        Portainer)    install_portainer ;;
        Supabase)     install_supabase ;;
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
  supabase_db_data:

networks:
  docker_network:
    driver: bridge
EOF

# Запуск контейнеров
dialog --infobox "\n🚀 Запуск контейнеров...\nЭто может занять несколько минут.\n" 8 60

cd "$INSTALL_DIR"

if docker-compose up -d; then
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
    echo "  ⚠️  Сохраните эти данные!"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo -e "${GREEN}✓ Все сервисы запущены!${NC}"
    echo ""
else
    dialog --title "✗ ОШИБКА" --msgbox "Ошибка при запуске контейнеров!\n\nПроверьте логи:\ndocker-compose logs" 10 60
    clear
    exit 1
fi
