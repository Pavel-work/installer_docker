#!/bin/bash
# Универсальный установщик сервисов v2.0
# Запуск: curl -sSL https://raw.githubusercontent.com/user/repo/main/install.sh | sudo bash

# === Обработка запуска через curl | bash ===
# Если stdin не терминал (pipe), сохраняем скрипт во временный файл и запускаем заново,
# чтобы освободить stdin для интерактивного ввода в dialog.
if [ ! -t 0 ]; then
    TMP_SCRIPT=$(mktemp)
    trap 'rm -f "$TMP_SCRIPT"' EXIT
    cat > "$TMP_SCRIPT"
    exec bash "$TMP_SCRIPT" "$@"
fi

set -euo pipefail

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# === Глобальные переменные ===
STATE_DIR="/root/.server-setup-state"
STATE_FILE="$STATE_DIR/state.cfg"
SELECTED_FILE="$STATE_DIR/selected_services.cfg"
PARAMS_FILE="$STATE_DIR/params.env"
SETUP_DIR="/root/server-setup"
TEMP_FILE=$(mktemp)
REAL_USER="${SUDO_USER:-$USER}"

cleanup() { rm -f "$TEMP_FILE"; }
trap cleanup EXIT INT TERM

save_state() { mkdir -p "$STATE_DIR"; echo "$1" > "$STATE_FILE"; }
get_state() { if [[ -f "$STATE_FILE" ]]; then cat "$STATE_FILE"; else echo "start"; fi; }

save_selected_services() { 
    mkdir -p "$STATE_DIR"
    printf "%s\n" "${SELECTED_ARRAY[@]}" > "$SELECTED_FILE"
}
load_selected_services() { 
    SELECTED_ARRAY=()
    [[ -f "$SELECTED_FILE" ]] && mapfile -t SELECTED_ARRAY < "$SELECTED_FILE"
}

# Безопасное сохранение параметров (экранирование кавычек и спецсимволов через ${var@Q})
save_params() {
    mkdir -p "$STATE_DIR"
    cat > "$PARAMS_FILE" <<EOF
PGPASSWORD=${PGPASSWORD@Q}
JWT_SECRET=${JWT_SECRET@Q}
LLM_TYPE=${LLM_TYPE@Q}
LLM_API_KEY=${LLM_API_KEY@Q}
LLM_API_URL=${LLM_API_URL@Q}
DOMAIN=${DOMAIN@Q}
SUPABASE_DOMAIN=${SUPABASE_DOMAIN@Q}
N8N_PORT=${N8N_PORT@Q}
N8N_DB_POSTGRES=${N8N_DB_POSTGRES@Q}
APACHE_WWW_PATH=${APACHE_WWW_PATH@Q}
APACHE_HTTP_PORT=${APACHE_HTTP_PORT@Q}
QDRANT_PORT=${QDRANT_PORT@Q}
OLLAMA_PORT=${OLLAMA_PORT@Q}
EOF
    chmod 600 "$PARAMS_FILE"
}

load_params() {
    if [[ -f "$PARAMS_FILE" ]]; then
        source "$PARAMS_FILE"
    fi
    PGPASSWORD="${PGPASSWORD:-}"
    JWT_SECRET="${JWT_SECRET:-}"
    LLM_TYPE="${LLM_TYPE:-}"
    LLM_API_KEY="${LLM_API_KEY:-}"
    LLM_API_URL="${LLM_API_URL:-}"
    DOMAIN="${DOMAIN:-}"
    SUPABASE_DOMAIN="${SUPABASE_DOMAIN:-}"
    N8N_PORT="${N8N_PORT:-5678}"
    N8N_DB_POSTGRES="${N8N_DB_POSTGRES:-0}"
    APACHE_WWW_PATH="${APACHE_WWW_PATH:-$SETUP_DIR/www}"
    APACHE_HTTP_PORT="${APACHE_HTTP_PORT:-8080}"
    QDRANT_PORT="${QDRANT_PORT:-6333}"
    OLLAMA_PORT="${OLLAMA_PORT:-11434}"
}

check_port() {
    local port=$1
    # Надежная проверка порта через ss
    if ss -Htuln sport = :$port | grep -q .; then
        dialog --title "Ошибка" --msgbox "Порт $port уже занят. Выберите другой." 6 50
        return 1
    fi
    return 0
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
        usermod -aG docker "$REAL_USER" || true
        systemctl enable docker --now > /dev/null 2>&1
    fi
    if ! docker compose version &> /dev/null; then
        apt-get install -y docker-compose-plugin > /dev/null 2>&1
    fi
}

# === 1. Меню выбора сервисов ===
show_service_menu() {
    local args=(
        "postgres" "PostgreSQL" "off"
        "qdrant" "Qdrant" "off"
        "ollama" "Ollama" "off"
        "apache" "Apache" "off"
        "nginx_proxy" "Nginx Proxy Manager" "off"
        "portainer" "Portainer" "off"
        "supabase" "Supabase" "off"
        "n8n" "n8n" "off"
    )
    if [ ${#SELECTED_ARRAY[@]} -gt 0 ]; then
        for ((i=0; i<${#args[@]}; i+=3)); do
            for sel in "${SELECTED_ARRAY[@]}"; do
                [[ "${args[$i]}" == "$sel" ]] && args[$((i+2))]="on"
            done
        done
    fi
    
    dialog --clear --title "Шаг 1: Выбор сервисов" \
        --extra-button --extra-label "Выход" \
        --ok-label "Далее" \
        --checklist "Выберите нужное (Пробел - выбрать, Enter - далее).\n\n[Навигация: Стрелки, Tab]" 22 70 10 \
        "${args[@]}" 2> "$TEMP_FILE"
    
    local res=$?
    if [ $res -eq 3 ] || [ $res -eq 1 ]; then return 1; fi # Выход или Cancel
    
    SELECTED=$(cat "$TEMP_FILE")
    SELECTED_ARRAY=()
    for item in $SELECTED; do
        SELECTED_ARRAY+=("$(echo "$item" | tr -d '"')")
    done
    
    if [ ${#SELECTED_ARRAY[@]} -eq 0 ]; then
        dialog --msgbox "Вы ничего не выбрали. Выберите хотя бы один сервис." 6 50
        return 1
    fi
    
    save_selected_services
    return 0
}

# Подсказка для ввода
INPUT_HINT="
\n\nВставка: Нажмите правой клавишей миши 
\nКопирование: Удерживайте Shift и просто выделите мышью, текст будет скопирован
\nНавигация: Tab для перехода к кнопкам"

# === 2. Ввод параметров (с навигацией назад) ===
step_postgres() {
    local hint="Введите пароль admin (оставте пусто = генерируется автоматически)$INPUT_HINT"
    dialog --clear --title "Шаг 2: PostgreSQL" \
        --extra-button --extra-label "Назад" \
        --ok-label "Далее" \
        --inputbox "$hint" 50 70 "$PGPASSWORD" 2> "$TEMP_FILE"
    local res=$?
    [ $res -eq 3 ] && return 1 # Назад
    [ $res -eq 1 ] && return 1 # Cancel
    
    PGPASSWORD=$(cat "$TEMP_FILE")
    if [ -z "$PGPASSWORD" ]; then
        PGPASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
        dialog --msgbox "Сгенерирован пароль: $PGPASSWORD\n\nЗапомните или скопируйте его!" 8 60
    fi
    return 0
}

step_jwt() {
    local hint="JWT Secret (нужен для Supabase и др. Пусто = сгенерировать)$INPUT_HINT"
    dialog --clear --title "Шаг 3: JWT Secret" \
        --extra-button --extra-label "Назад" \
        --ok-label "Далее" \
        --inputbox "$hint" 14 70 "$JWT_SECRET" 2> "$TEMP_FILE"
    local res=$?
    [ $res -eq 3 ] && return 1
    [ $res -eq 1 ] && return 1
    
    JWT_SECRET=$(cat "$TEMP_FILE")
    [ -z "$JWT_SECRET" ] && JWT_SECRET=$(openssl rand -hex 32)
    return 0
}

step_llm() {
    dialog --clear --title "Шаг 4: LLM (Нейросети)" \
        --extra-button --extra-label "Назад" \
        --ok-label "Далее" \
        --radiolist "Выберите провайдера:" 15 60 4 \
        "ollama" "Ollama (Локально)" on \
        "openai" "OpenAI" off \
        "anthropic" "Anthropic" off \
        2> "$TEMP_FILE"
    local res=$?
    [ $res -eq 3 ] && return 1
    [ $res -eq 1 ] && return 1
    
    LLM_TYPE=$(cat "$TEMP_FILE")
    case "$LLM_TYPE" in
        openai)
            dialog --extra-button --extra-label "Назад" --ok-label "Далее" \
                --passwordbox "OpenAI API key (sk-...)$INPUT_HINT" 12 70 2> "$TEMP_FILE"
            [ $? -eq 3 ] && return 1
            LLM_API_KEY=$(cat "$TEMP_FILE")
            LLM_API_URL="https://api.openai.com/v1"
            ;;
        anthropic)
            dialog --extra-button --extra-label "Назад" --ok-label "Далее" \
                --passwordbox "Anthropic API key$INPUT_HINT" 12 70 2> "$TEMP_FILE"
            [ $? -eq 3 ] && return 1
            LLM_API_KEY=$(cat "$TEMP_FILE")
            LLM_API_URL="https://api.anthropic.com/v1"
            ;;
        ollama)
            LLM_API_URL="http://ollama:11434"
            ;;
    esac
    return 0
}

step_domain() {
    dialog --clear --title "Шаг 5: Домены" \
        --extra-button --extra-label "Назад" \
        --ok-label "Далее" \
        --form "Укажите домены (можно оставить пустым)$INPUT_HINT" 14 70 0 \
        "Основной домен:" 1 2 "$DOMAIN" 1 20 40 0 \
        "Поддомен Supabase:" 3 2 "$SUPABASE_DOMAIN" 3 20 40 0 \
        2> "$TEMP_FILE"
    local res=$?
    [ $res -eq 3 ] && return 1
    [ $res -eq 1 ] && return 1
    
    local domains
    mapfile -t domains < "$TEMP_FILE"
    DOMAIN="${domains[0]}"
    SUPABASE_DOMAIN="${domains[1]}"
    return 0
}

step_ports() {
    while true; do
        local form_args=()
        local row=1
        
        if [[ " ${SELECTED_ARRAY[@]} " =~ "n8n" ]]; then
            form_args+=("Порт n8n:" $row 2 "$N8N_PORT" $row 20 15 0)
            ((row+=2))
        fi
        if [[ " ${SELECTED_ARRAY[@]} " =~ "apache" ]]; then
            form_args+=("Порт Apache:" $row 2 "$APACHE_HTTP_PORT" $row 20 15 0)
            ((row+=2))
        fi
        if [[ " ${SELECTED_ARRAY[@]} " =~ "qdrant" ]]; then
            form_args+=("Порт Qdrant:" $row 2 "$QDRANT_PORT" $row 20 15 0)
            ((row+=2))
        fi
        if [[ " ${SELECTED_ARRAY[@]} " =~ "ollama" ]]; then
            form_args+=("Порт Ollama:" $row 2 "$OLLAMA_PORT" $row 20 15 0)
            ((row+=2))
        fi
        
        if [ ${#form_args[@]} -eq 0 ]; then return 0; fi
        
        local height=$((row + 5))
        [ $height -gt 20 ] && height=20
        
        dialog --clear --title "Шаг 6: Порты сервисов" \
            --extra-button --extra-label "Назад" \
            --ok-label "Далее" \
            --form "Укажите порты (Tab для перехода)$INPUT_HINT" $height 70 0 \
            "${form_args[@]}" 2> "$TEMP_FILE"
        
        local res=$?
        [ $res -eq 3 ] && return 1
        [ $res -eq 1 ] && return 1
        
        local ports
        mapfile -t ports < "$TEMP_FILE"
        local idx=0
        local ports_ok=true
        
        if [[ " ${SELECTED_ARRAY[@]} " =~ "n8n" ]]; then
            N8N_PORT="${ports[$idx]}"
            if ! check_port "$N8N_PORT"; then ports_ok=false; fi
            ((idx++))
        fi
        if [[ " ${SELECTED_ARRAY[@]} " =~ "apache" ]]; then
            APACHE_HTTP_PORT="${ports[$idx]}"
            if ! check_port "$APACHE_HTTP_PORT"; then ports_ok=false; fi
            ((idx++))
        fi
        if [[ " ${SELECTED_ARRAY[@]} " =~ "qdrant" ]]; then
            QDRANT_PORT="${ports[$idx]}"
            if ! check_port "$QDRANT_PORT"; then ports_ok=false; fi
            ((idx++))
        fi
        if [[ " ${SELECTED_ARRAY[@]} " =~ "ollama" ]]; then
            OLLAMA_PORT="${ports[$idx]}"
            if ! check_port "$OLLAMA_PORT"; then ports_ok=false; fi
            ((idx++))
        fi
        
        if [ "$ports_ok" = true ]; then break; fi
    done
    
    if [[ " ${SELECTED_ARRAY[@]} " =~ "n8n" ]] && [[ " ${SELECTED_ARRAY[@]} " =~ "postgres" ]]; then
        dialog --extra-button --extra-label "Назад" --ok-label "Далее" \
            --yesno "Использовать PostgreSQL для базы данных n8n?" 8 50
        local db_res=$?
        [ $db_res -eq 3 ] && return 1
        [ $db_res -eq 0 ] && N8N_DB_POSTGRES=1 || N8N_DB_POSTGRES=0
    fi
    
    if [[ " ${SELECTED_ARRAY[@]} " =~ "apache" ]]; then
        dialog --extra-button --extra-label "Назад" --ok-label "Далее" \
            --inputbox "Путь для сайтов Apache:$INPUT_HINT" 12 70 "$APACHE_WWW_PATH" 2> "$TEMP_FILE"
        [ $? -eq 3 ] && return 1
        APACHE_WWW_PATH=$(cat "$TEMP_FILE")
        [ -z "$APACHE_WWW_PATH" ] && APACHE_WWW_PATH="$SETUP_DIR/www"
        APACHE_WWW_PATH=$(realpath -m "$APACHE_WWW_PATH")
        mkdir -p "$APACHE_WWW_PATH" "$APACHE_WWW_PATH/conf"
        [ ! -f "$APACHE_WWW_PATH/index.html" ] && echo "<h1>It works!</h1>" > "$APACHE_WWW_PATH/index.html"
    fi
    
    return 0
}

input_parameters() {
    local step=1
    while true; do
        case $step in
            1) step_postgres && ((step++)) || return 1 ;;
            2) step_jwt && ((step++)) || ((step--)) ;;
            3) step_llm && ((step++)) || ((step--)) ;;
            4) step_domain && ((step++)) || ((step--)) ;;
            5) step_ports && ((step++)) || ((step--)) ;;
            6) break ;;
        esac
    done
    save_params
    return 0
}

# === 3. Сеть ===
setup_network() {
    docker network inspect internal_network &>/dev/null || docker network create internal_network > /dev/null
    mkdir -p "$SETUP_DIR"
    cd "$SETUP_DIR"
    cat > .env <<EOF
POSTGRES_PASSWORD=${PGPASSWORD}
JWT_SECRET=${JWT_SECRET}
LLM_TYPE=${LLM_TYPE}
LLM_API_KEY=${LLM_API_KEY}
LLM_API_URL=${LLM_API_URL}
DOMAIN=${DOMAIN}
SUPABASE_DOMAIN=${SUPABASE_DOMAIN}
N8N_PORT=${N8N_PORT}
N8N_DB_POSTGRES=${N8N_DB_POSTGRES}
APACHE_WWW_PATH=${APACHE_WWW_PATH}
APACHE_HTTP_PORT=${APACHE_HTTP_PORT}
QDRANT_PORT=${QDRANT_PORT}
OLLAMA_PORT=${OLLAMA_PORT}
EOF
    chmod 600 .env
}

# === 4. Supabase (с правильными JWT) ===
setup_supabase() {
    [[ ! " ${SELECTED_ARRAY[@]} " =~ "supabase" ]] && return 0
    cd "$SETUP_DIR"
    if [ ! -d "supabase-docker" ]; then
        git clone --depth 1 --filter=blob:none --sparse https://github.com/supabase/supabase > /dev/null 2>&1
        cd supabase
        git sparse-checkout set docker utils > /dev/null 2>&1
        cd ..
        mv supabase/docker supabase-docker
        cp -r supabase/utils supabase-docker/utils 2>/dev/null || true
        rm -rf supabase
    fi
    cd supabase-docker
    cp .env.example .env
    
    # Генерируем JWT ключи через официальный скрипт Supabase
    if [ -f "utils/generate-keys.sh" ]; then
        bash utils/generate-keys.sh > .env.keys 2>/dev/null
        ANON_KEY=$(grep "^ANON_KEY=" .env.keys | cut -d'=' -f2- | tr -d '"')
        SERVICE_ROLE_KEY=$(grep "^SERVICE_ROLE_KEY=" .env.keys | cut -d'=' -f2- | tr -d '"')
        SECRET_KEY_BASE=$(grep "^SECRET_KEY_BASE=" .env.keys | cut -d'=' -f2- | tr -d '"')
        VAULT_ENC_KEY=$(grep "^VAULT_ENC_KEY=" .env.keys | cut -d'=' -f2- | tr -d '"')
        rm -f .env.keys
    else
        ANON_KEY=$(openssl rand -hex 32)
        SERVICE_ROLE_KEY=$(openssl rand -hex 32)
        SECRET_KEY_BASE=$(openssl rand -hex 32)
        VAULT_ENC_KEY=$(openssl rand -hex 32)
    fi
    
    PG_META_CRYPTO_KEY=$(openssl rand -hex 32)
    LOGFILE_PUBLIC_ACCESS_TOKEN=$(openssl rand -hex 32)
    LOGFILE_PRIVATE_ACCESS_TOKEN=$(openssl rand -hex 32)
    S3_PROTOCOL_ACCESS_KEY_ID=$(openssl rand -hex 16)
    S3_PROTOCOL_ACCESS_KEY_SECRET=$(openssl rand -hex 32)
    MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
    DASHBOARD_PASSWORD=$(openssl rand -hex 12)
    
    sed -i "s/^ANON_KEY=.*/ANON_KEY=$ANON_KEY/" .env
    sed -i "s/^SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY/" .env
    sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$SECRET_KEY_BASE/" .env
    sed -i "s/^VAULT_ENC_KEY=.*/VAULT_ENC_KEY=$VAULT_ENC_KEY/" .env
    sed -i "s/^PG_META_CRYPTO_KEY=.*/PGMETA_CRYPTO_KEY=$PG_META_CRYPTO_KEY/" .env
    sed -i "s/^LOGFILE_PUBLIC_ACCESS_TOKEN=.*/LOGFILE_PUBLIC_ACCESS_TOKEN=$LOGFILE_PUBLIC_ACCESS_TOKEN/" .env
    sed -i "s/^LOGFILE_PRIVATE_ACCESS_TOKEN=.*/LOGFILE_PRIVATE_ACCESS_TOKEN=$LOGFILE_PRIVATE_ACCESS_TOKEN/" .env
    sed -i "s/^S3_PROTOCOL_ACCESS_KEY_ID=.*/S3_PROTOCOL_ACCESS_KEY_ID=$S3_PROTOCOL_ACCESS_KEY_ID/" .env
    sed -i "s/^S3_PROTOCOL_ACCESS_KEY_SECRET=.*/S3_PROTOCOL_ACCESS_KEY_SECRET=$S3_PROTOCOL_ACCESS_KEY_SECRET/" .env
    sed -i "s/^MINIO_ROOT_PASSWORD=.*/MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD/" .env
    sed -i "s/^DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD/" .env
    
    local PGPASSWORD_ESC=$(printf '%s\n' "$PGPASSWORD" | sed -e 's/[\/&]/\\&/g')
    sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${PGPASSWORD_ESC}/" .env
    sed -i "s/JWT_SECRET=.*/JWT_SECRET=${JWT_SECRET}/" .env
    
    if [ -n "$SUPABASE_DOMAIN" ]; then
        sed -i "s|^PUBLIC_URL=.*|PUBLIC_URL=https://${SUPABASE_DOMAIN}|" .env
        sed -i "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://${SUPABASE_DOMAIN}|" .env
        sed -i "s|^SITE_URL=.*|SITE_URL=https://${SUPABASE_DOMAIN}|" .env
    fi
    
    if ! grep -q "internal_network" docker-compose.yml; then
        cat >> docker-compose.yml <<EOF

networks:
  internal_network:
    external: true
EOF
    fi
    
    docker compose -p supabase up -d > /dev/null 2>&1
    sleep 5
    for container in $(docker ps --filter "name=supabase" --format "{{.Names}}"); do
        docker network connect internal_network "$container" 2>/dev/null || true
    done
    cd ..
}

# === 5. Генерация docker-compose.yml ===
generate_compose_file() {
    cd "$SETUP_DIR"
    cat > docker-compose.yml <<EOF
networks:
  internal_network:
    external: true
volumes:
EOF
    [[ " ${SELECTED_ARRAY[@]} " =~ "postgres" ]] && echo "  postgres_data:" >> docker-compose.yml
    [[ " ${SELECTED_ARRAY[@]} " =~ "qdrant" ]] && echo "  qdrant_storage:" >> docker-compose.yml
    [[ " ${SELECTED_ARRAY[@]} " =~ "ollama" ]] && echo "  ollama_data:" >> docker-compose.yml
    [[ " ${SELECTED_ARRAY[@]} " =~ "nginx_proxy" ]] && { echo "  npm_data:" >> docker-compose.yml; echo "  npm_letsencrypt:" >> docker-compose.yml; }
    [[ " ${SELECTED_ARRAY[@]} " =~ "portainer" ]] && echo "  portainer_data:" >> docker-compose.yml
    [[ " ${SELECTED_ARRAY[@]} " =~ "n8n" ]] && echo "  n8n_data:" >> docker-compose.yml
    echo -e "\nservices:" >> docker-compose.yml
    
    if [[ " ${SELECTED_ARRAY[@]} " =~ "postgres" ]]; then
        cat >> docker-compose.yml <<EOF
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: ${PGPASSWORD}
      POSTGRES_DB: appdb
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - internal_network
EOF
    fi
    
    if [[ " ${SELECTED_ARRAY[@]} " =~ "qdrant" ]]; then
        cat >> docker-compose.yml <<EOF
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    ports:
      - "${QDRANT_PORT}:6333"
    volumes:
      - qdrant_storage:/qdrant/storage
    networks:
      - internal_network
EOF
    fi
    
    if [[ " ${SELECTED_ARRAY[@]} " =~ "ollama" ]]; then
        cat >> docker-compose.yml <<EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "${OLLAMA_PORT}:11434"
    environment:
      OLLAMA_HOST: 0.0.0.0
    volumes:
      - ollama_data:/root/.ollama
    networks:
      - internal_network
EOF
    fi
    
    if [[ " ${SELECTED_ARRAY[@]} " =~ "apache" ]]; then
        cat >> docker-compose.yml <<EOF
  apache:
    image: httpd:2.4-alpine
    container_name: apache
    restart: unless-stopped
    ports:
      - "${APACHE_HTTP_PORT}:80"
    volumes:
      - "${APACHE_WWW_PATH}:/usr/local/apache2/htdocs/"
      - "${APACHE_WWW_PATH}/conf:/usr/local/apache2/conf/extra/"
    networks:
      - internal_network
EOF
    fi
    
    if [[ " ${SELECTED_ARRAY[@]} " =~ "nginx_proxy" ]]; then
        cat >> docker-compose.yml <<EOF
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - npm_data:/data
      - npm_letsencrypt:/etc/letsencrypt
    networks:
      - internal_network
EOF
    fi
    
    if [[ " ${SELECTED_ARRAY[@]} " =~ "portainer" ]]; then
        cat >> docker-compose.yml <<EOF
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    ports:
      - "9000:9000"
    networks:
      - internal_network
EOF
    fi
    
    if [[ " ${SELECTED_ARRAY[@]} " =~ "n8n" ]]; then
        local n8n_db_env=""
        if [ "${N8N_DB_POSTGRES:-0}" -eq 1 ]; then
            # ИСПРАВЛЕНО: Правильные отступы для YAML
            n8n_db_env="
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_USER: admin
      DB_POSTGRESDB_PASSWORD: ${PGPASSWORD}
      DB_POSTGRESDB_DATABASE: n8n"
        fi
        cat >> docker-compose.yml <<EOF
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    environment:${n8n_db_env}
      N8N_HOST: ${DOMAIN:-localhost}
      N8N_PORT: ${N8N_PORT}
      WEBHOOK_URL: http://${DOMAIN:-localhost}:${N8N_PORT}
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - internal_network
EOF
    fi
}

# === 6. Запуск (с умным ожиданием БД) ===
start_containers() {
    cd "$SETUP_DIR"
    docker compose up -d > /dev/null 2>&1
    
    if [[ " ${SELECTED_ARRAY[@]} " =~ "n8n" ]] && [ "${N8N_DB_POSTGRES:-0}" -eq 1 ]; then
        # ИСПРАВЛЕНО: Ожидание готовности Postgres
        local timeout=60
        while ! docker exec postgres pg_isready -U admin &>/dev/null; do
            sleep 2
            timeout=$((timeout - 2))
            if [ $timeout -le 0 ]; then break; fi
        done
        docker exec postgres psql -U admin -c "CREATE DATABASE n8n;" 2>/dev/null || true
    fi
}

# === 7. SSL инструкция ===
configure_nginx_ssl() {
    [[ ! " ${SELECTED_ARRAY[@]} " =~ "nginx_proxy" ]] || [ -z "$DOMAIN" ] && return 0
    sleep 5
    cat > "$SETUP_DIR/auto_ssl_commands.sh" <<EOF
# NPM: http://$(hostname -I | awk '{print $1}'):81
# login: admin@example.com pass: changeme
EOF
    chmod +x "$SETUP_DIR/auto_ssl_commands.sh"
}

# === 8. Переустановка ===
reinstall_service() {
    local svc=$1
    cd "$SETUP_DIR"
    case $svc in
        supabase) docker compose -p supabase down -v; rm -rf supabase-docker; setup_supabase ;;
        *) docker compose stop $svc || true; docker compose rm -f $svc || true; generate_compose_file; docker compose up -d $svc ;;
    esac
    dialog --msgbox "$svc переустановлен." 6 40
}

# === 9. Финальное окно ===
show_summary() {
    FIRST_IP=$(hostname -I | awk '{print $1}')
    SUMMARY="✅ Установка завершена!
\nIP сервера: $FIRST_IP
"
    [[ -n "$DOMAIN" ]] && SUMMARY+="\nДомен: $DOMAIN
"
    SUMMARY+="
\nПароль PostgreSQL: $PGPASSWORD
\nJWT Secret: $JWT_SECRET
"
    echo -e "$SUMMARY" > "$STATE_DIR/summary.txt"
    dialog --title "Готово (можно копировать мышкой)" --textbox "$STATE_DIR/summary.txt" 15 60
}

# === Главная функция установки с прогресс-баром ===
run_installation_process() {
    {
        echo "5"
        echo "### Проверка системы и установка Docker..."
        install_docker
        
        echo "15"
        echo "### Настройка внутренней сети..."
        setup_network
        
        echo "30"
        echo "### Развертывание Supabase (может занять время)..."
        setup_supabase
        
        echo "60"
        echo "### Генерация конфигурации сервисов..."
        generate_compose_file
        
        echo "80"
        echo "### Запуск контейнеров и создание БД..."
        start_containers
        
        echo "95"
        echo "### Финальная настройка..."
        configure_nginx_ssl
        
        echo "100"
        echo "### Установка успешно завершена!"
        sleep 2
    } | dialog --title "Установка сервисов" --gauge "Пожалуйста, подождите. Идет настройка сервера..." 12 70 0
}

# === 10. Главная ===
main() {
    if ! grep -qi "ubuntu\|debian" /etc/os-release; then echo "Только Ubuntu/Debian"; exit 1; fi
    if [ "$EUID" -ne 0 ]; then echo "Запусти с sudo"; exit 1; fi
    if ! command -v dialog &> /dev/null; then apt-get update > /dev/null && apt-get install -y dialog > /dev/null; fi
    
    local current_state=$(get_state)
    load_selected_services
    load_params
    
    if [ $# -eq 2 ] && [ "$1" == "--reinstall" ]; then 
        reinstall_service "$2"
        exit 0 
    fi
    
    case "$current_state" in
        "start")
            show_service_menu || { save_state "start"; main; return; }
            
            input_parameters || { show_service_menu || { save_state "start"; main; return; }; }
            
            run_installation_process
            save_state "completed"
            show_summary
            ;;
        "completed")
            dialog --menu "Установка завершена. Действие:" 12 60 3 \
                "1" "Добавить/удалить сервисы" \
                "2" "Переустановить сервис" \
                "3" "Выйти" 2> "$TEMP_FILE"
            case $(cat "$TEMP_FILE") in
                1) 
                    show_service_menu
                    input_parameters
                    run_installation_process
                    show_summary 
                    ;;
                2)
                    local installed=()
                    for svc in postgres qdrant ollama apache nginx-proxy-manager portainer supabase n8n; do
                        docker ps --format '{{.Names}}' | grep -q "^$svc$" && installed+=("$svc" "$svc" off)
                    done
                    [ ${#installed[@]} -eq 0 ] && { dialog --msgbox "Нет установленных сервисов." 6 40; exit 0; }
                    dialog --checklist "Выберите:" 15 50 6 "${installed[@]}" 2> "$TEMP_FILE"
                    for svc in $(cat "$TEMP_FILE" | tr -d '"'); do reinstall_service "$svc"; done
                    ;;
                *) exit 0 ;;
            esac
            ;;
        *) rm -rf "$STATE_DIR"; save_state "start"; main ;;
    esac
}

main "$@"
