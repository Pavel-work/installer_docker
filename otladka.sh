#!/bin/bash
# Универсальный установщик сервисов v3.2 (DEBUG MODE)
# Отладочная версия с подробным логированием

# === Обработка pipe-запуска ===
if [ ! -t 0 ] && [ -z "$SCRIPT_SELF_EXECUTED" ]; then
  export SCRIPT_SELF_EXECUTED=1
  exec bash <(cat) "$@"
fi

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
LOG_FILE="/tmp/installer-debug.log"
REAL_USER="${SUDO_USER:-$USER}"

# Логирование всех действий
exec 3>&1 4>&2
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== DEBUG LOG START: $(date) ===" >> "$LOG_FILE"

cleanup_temp() { rm -f "$TEMP_FILE" 2>/dev/null || true; }
trap cleanup_temp EXIT INT TERM

save_state() { mkdir -p "$STATE_DIR" 2>/dev/null; echo "$1" > "$STATE_FILE"; }
get_state() { [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "start"; }

save_selected() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  printf '%s\n' "${SELECTED_ARRAY[@]}" > "$SELECTED_FILE"
}

load_selected() {
  SELECTED_ARRAY=()
  [[ -f "$SELECTED_FILE" ]] && while IFS= read -r line; do
    [[ -n "$line" ]] && SELECTED_ARRAY+=("$line")
  done < "$SELECTED_FILE"
}

save_params() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  cat > "$PARAMS_FILE" <<EOF
PGPASSWORD=${PGPASSWORD@Q}
JWT_SECRET=${JWT_SECRET@Q}
LLM_TYPE=${LLM_TYPE@Q}
LLM_API_KEY=${LLM_API_KEY@Q}
LLM_API_URL=${LLM_API_URL@Q}
DOMAIN_MAIN=${DOMAIN_MAIN@Q}
SUPABASE_DOMAIN=${SUPABASE_DOMAIN@Q}
N8N_PORT=${N8N_PORT@Q}
N8N_DOMAIN=${N8N_DOMAIN@Q}
N8N_DB_POSTGRES=${N8N_DB_POSTGRES@Q}
APACHE_WWW_PATH=${APACHE_WWW_PATH@Q}
APACHE_PORT=${APACHE_PORT@Q}
APACHE_DOMAIN=${APACHE_DOMAIN@Q}
QDRANT_PORT=${QDRANT_PORT@Q}
QDRANT_DOMAIN=${QDRANT_DOMAIN@Q}
OLLAMA_PORT=${OLLAMA_PORT@Q}
OLLAMA_DOMAIN=${OLLAMA_DOMAIN@Q}
PORTAINER_DOMAIN=${PORTAINER_DOMAIN@Q}
NPM_ENABLED=${NPM_ENABLED@Q}
EOF
  chmod 600 "$PARAMS_FILE" 2>/dev/null || true
}

load_params() {
  [[ -f "$PARAMS_FILE" ]] && source "$PARAMS_FILE"
  PGPASSWORD="${PGPASSWORD:-}"
  JWT_SECRET="${JWT_SECRET:-}"
  LLM_TYPE="${LLM_TYPE:-ollama}"
  LLM_API_KEY="${LLM_API_KEY:-}"
  LLM_API_URL="${LLM_API_URL:-}"
  DOMAIN_MAIN="${DOMAIN_MAIN:-}"
  SUPABASE_DOMAIN="${SUPABASE_DOMAIN:-}"
  N8N_PORT="${N8N_PORT:-5678}"
  N8N_DOMAIN="${N8N_DOMAIN:-}"
  N8N_DB_POSTGRES="${N8N_DB_POSTGRES:-0}"
  APACHE_WWW_PATH="${APACHE_WWW_PATH:-$SETUP_DIR/www}"
  APACHE_PORT="${APACHE_PORT:-8080}"
  APACHE_DOMAIN="${APACHE_DOMAIN:-}"
  QDRANT_PORT="${QDRANT_PORT:-6333}"
  QDRANT_DOMAIN="${QDRANT_DOMAIN:-}"
  OLLAMA_PORT="${OLLAMA_PORT:-11434}"
  OLLAMA_DOMAIN="${OLLAMA_DOMAIN:-}"
  PORTAINER_DOMAIN="${PORTAINER_DOMAIN:-}"
  NPM_ENABLED="${NPM_ENABLED:-0}"
}

read_secure_input() {
  local prompt="$1" default="$2" var_name="$3"
  local hint=$'\n[Вставка: Shift+Insert или ПКМ мыши]\n[Или введите @/путь/к/файлу для загрузки ключа]'
  
  while true; do
    dialog --clear --title "Ввод параметра" --inputbox "$prompt$hint" 15 70 "$default" 2>"$TEMP_FILE"
    local res=$?
    [[ $res -ne 0 ]] && return $res
    
    local val=$(cat "$TEMP_FILE")
    if [[ "$val" =~ ^@(.+)$ ]]; then
      local fpath="${BASH_REMATCH[1]}"
      if [[ -r "$fpath" ]]; then
        val=$(<"$fpath")
        dialog --msgbox "✅ Значение загружено из $fpath" 6 50
      else
        dialog --msgbox "❌ Файл не найден или нет прав: $fpath" 6 50
        continue
      fi
    fi
    declare -g "$var_name=$val"
    return 0
  done
}

check_port() {
  local port=$1
  if command -v ss &>/dev/null && ss -Htuln sport = :$port 2>/dev/null | grep -q .; then
    dialog --title "Ошибка" --msgbox "Порт $port уже занят." 6 40
    return 1
  fi
  return 0
}

# === ОТЛАДОЧНАЯ установка Docker ===
install_docker() {
  echo "[$(date +%T)] Проверка Docker..." >&3
  if ! command -v docker &>/dev/null; then
    echo "[$(date +%T)] Docker не найден, устанавливаю..." >&3
    curl -fsSL https://get.docker.com | sh 2>&1 | while read line; do echo "[$(date +%T)] $line" >&3; done
    usermod -aG docker "$REAL_USER" 2>/dev/null || true
    systemctl enable docker --now 2>&1 | while read line; do echo "[$(date +%T)] $line" >&3; done
  else
    echo "[$(date +%T)] Docker уже установлен" >&3
  fi
  
  if ! docker compose version &>/dev/null; then
    echo "[$(date +%T)] Установка docker-compose-plugin..." >&3
    apt-get update -qq 2>&1 | while read line; do echo "[$(date +%T)] $line" >&3; done
    apt-get install -y docker-compose-plugin 2>&1 | while read line; do echo "[$(date +%T)] $line" >&3; done
  else
    echo "[$(date +%T)] docker compose уже доступен" >&3
  fi
  echo "[$(date +%T)] Docker готов" >&3
}

show_service_menu() {
  local args=(
    "postgres" "PostgreSQL (БД)" "off"
    "qdrant" "Qdrant (Векторная БД)" "off"
    "ollama" "Ollama (Локальные LLM)" "off"
    "apache" "Apache (Веб-сервер)" "off"
    "nginx_proxy" "Nginx Proxy Manager (Прокси+SSL)" "off"
    "portainer" "Portainer (Управление Docker)" "off"
    "supabase" "Supabase (BaaS платформа)" "off"
    "n8n" "n8n (Автоматизация)" "off"
  )
  
  if [ ${#SELECTED_ARRAY[@]} -gt 0 ]; then
    for ((i=0; i<${#args[@]}; i+=3)); do
      for sel in "${SELECTED_ARRAY[@]}"; do
        [[ "${args[$i]}" == "$sel" ]] && args[$((i+2))]="on"
      done
    done
  fi
  
  dialog --clear --title "📦 Шаг 1: Выберите сервисы" \
    --extra-button --extra-label "Выход" --ok-label "Далее ▶" \
    --checklist "Пробел = выбор, Enter = далее\n[Навигация: Стрелки, Tab]" \
    20 70 10 "${args[@]}" 2>"$TEMP_FILE"
  
  local res=$?
  [[ $res -eq 1 || $res -eq 3 ]] && return 1
  
  SELECTED_ARRAY=()
  for item in $(cat "$TEMP_FILE" 2>/dev/null | tr -d '"'); do
    SELECTED_ARRAY+=("$item")
  done
  
  if [ ${#SELECTED_ARRAY[@]} -eq 0 ]; then
    dialog --msgbox "⚠ Выберите хотя бы один сервис." 6 50
    return 1
  fi
  
  echo "[$(date +%T)] Выбрано: ${SELECTED_ARRAY[*]}" >&3
  save_selected
  return 0
}

input_parameters() {
  echo "[$(date +%T)] Начало ввода параметров..." >&3
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "postgres" || " ${SELECTED_ARRAY[*]} " =~ "supabase" ]]; then
    while true; do
      read_secure_input "🔐 Пароль PostgreSQL (admin):" "$PGPASSWORD" "PGPASSWORD" || return 1
      [[ -n "$PGPASSWORD" ]] && break
      PGPASSWORD=$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-20)
      dialog --msgbox "🎲 Сгенерирован: $PGPASSWORD" 8 60
      break
    done
  fi
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]]; then
    read_secure_input "🔑 JWT Secret (пусто = авто):" "$JWT_SECRET" "JWT_SECRET" || return 1
    [[ -z "$JWT_SECRET" ]] && JWT_SECRET=$(openssl rand -hex 32)
    
    dialog --clear --title "🌐 Supabase домен" --inputbox "Поддомен для Supabase (пусто = без домена):" 10 70 "$SUPABASE_DOMAIN" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return 1
    SUPABASE_DOMAIN=$(cat "$TEMP_FILE")
  fi
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]]; then
    NPM_ENABLED=1
    dialog --clear --title "🌍 Основной домен" --inputbox "Введите основной домен (например: example.com):" 10 70 "$DOMAIN_MAIN" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return 1
    DOMAIN_MAIN=$(cat "$TEMP_FILE")
    
    if [[ -n "$DOMAIN_MAIN" ]]; then
      for svc in n8n apache qdrant ollama portainer supabase; do
        if [[ " ${SELECTED_ARRAY[*]} " =~ "$svc" ]]; then
          local default_domain="${svc}.${DOMAIN_MAIN}"
          [[ "$svc" == "supabase" && -n "$SUPABASE_DOMAIN" ]] && default_domain="$SUPABASE_DOMAIN"
          
          dialog --yesno "🔗 Проксировать $svc через NPM с SSL?\nДомен: $default_domain" 10 60 || continue
          local var_name="${svc^^}_DOMAIN"
          declare -g "$var_name=$default_domain"
        fi
      done
    fi
  fi
  
  for svc in n8n apache qdrant ollama; do
    if [[ " ${SELECTED_ARRAY[*]} " =~ "$svc" ]]; then
      local domain_var="${svc^^}_DOMAIN"
      local has_domain="${!domain_var}"
      
      if [[ "$NPM_ENABLED" -eq 1 && -n "$has_domain" ]]; then
        continue
      fi
      
      local port_var="${svc^^}_PORT"
      local current_port="${!port_var}"
      local default_port=""
      case "$svc" in
        n8n) default_port=5678 ;; apache) default_port=8080 ;;
        qdrant) default_port=6333 ;; ollama) default_port=11434 ;;
      esac
      current_port="${current_port:-$default_port}"
      
      while true; do
        dialog --clear --title "🔌 Порт $svc" --inputbox "Порт для $svc (публикуется наружу):" 10 70 "$current_port" 2>"$TEMP_FILE"
        [[ $? -ne 0 ]] && return 1
        local new_port=$(cat "$TEMP_FILE")
        check_port "$new_port" && { declare -g "$port_var=$new_port"; break; }
      done
    fi
  done
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && " ${SELECTED_ARRAY[*]} " =~ "postgres" ]]; then
    dialog --yesno "💾 Использовать PostgreSQL для базы n8n?\n(Рекомендуется вместо SQLite)" 8 50
    [[ $? -eq 0 ]] && N8N_DB_POSTGRES=1 || N8N_DB_POSTGRES=0
  fi
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]]; then
    dialog --clear --title "📁 Путь Apache" --inputbox "Корневая папка для сайтов:" 10 70 "$APACHE_WWW_PATH" 2>"$TEMP_FILE"
    [[ $? -eq 0 ]] && {
      APACHE_WWW_PATH=$(cat "$TEMP_FILE")
      [[ -z "$APACHE_WWW_PATH" ]] && APACHE_WWW_PATH="$SETUP_DIR/www"
      APACHE_WWW_PATH=$(realpath -m "$APACHE_WWW_PATH")
      mkdir -p "$APACHE_WWW_PATH" "$APACHE_WWW_PATH/conf"
      [ ! -f "$APACHE_WWW_PATH/index.html" ] && echo "<h1>It works!</h1>" > "$APACHE_WWW_PATH/index.html"
    }
  fi
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] || { [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]] && dialog --yesno "🤖 Подключить внешний LLM API к n8n?" 8 50; }; then
    dialog --clear --title "🤖 LLM провайдер" --radiolist "Выберите:" 15 60 4 \
      "ollama" "Ollama (локально)" on "openai" "OpenAI API" off "anthropic" "Anthropic" off \
      2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return 1
    LLM_TYPE=$(cat "$TEMP_FILE")
    
    case "$LLM_TYPE" in
      openai|anthropic)
        local api_url="https://api.${LLM_TYPE}.com/v1"
        [[ "$LLM_TYPE" == "anthropic" ]] && api_url="https://api.anthropic.com/v1"
        read_secure_input "🔑 API ключ ($LLM_TYPE):" "" "LLM_API_KEY" || return 1
        LLM_API_URL="$api_url"
        ;;
      ollama) LLM_API_URL="http://ollama:11434" ;;
    esac
  fi
  
  save_params
  echo "[$(date +%T)] Параметры сохранены" >&3
  return 0
}

setup_network() {
  echo "[$(date +%T)] Создание сети internal_network..." >&3
  if ! docker network inspect internal_network &>/dev/null; then
    docker network create internal_network 2>&1 | while read line; do echo "[$(date +%T)] $line" >&3; done
  fi
  
  mkdir -p "$SETUP_DIR" && cd "$SETUP_DIR"
  
  cat > .env <<EOF
# Auto-generated $(date +%F_%T)
EOF
  [[ -n "$PGPASSWORD" ]] && echo "POSTGRES_PASSWORD=${PGPASSWORD}" >> .env
  [[ -n "$JWT_SECRET" ]] && echo "JWT_SECRET=${JWT_SECRET}" >> .env
  [[ -n "$LLM_API_KEY" ]] && echo "LLM_API_KEY=${LLM_API_KEY}" >> .env
  [[ -n "$LLM_API_URL" ]] && echo "LLM_API_URL=${LLM_API_URL}" >> .env
  [[ -n "$DOMAIN_MAIN" ]] && echo "DOMAIN_MAIN=${DOMAIN_MAIN}" >> .env
  
  chmod 600 .env
  echo "[$(date +%T)] Сеть готова, .env создан" >&3
}

setup_supabase() {
  [[ ! " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && return 0
  
  echo "[$(date +%T)] Установка Supabase..." >&3
  cd "$SETUP_DIR"
  if [ ! -d "supabase-docker" ]; then
    echo "[$(date +%T)] Клонирование репозитория..." >&3
    git clone --depth 1 --filter=blob:none --sparse https://github.com/supabase/supabase 2>&1 | while read line; do echo "[$(date +%T)] $line" >&3; done
    (cd supabase && git sparse-checkout set docker utils 2>&1 | while read line; do echo "[$(date +%T)] $line" >&3; done)
    mv supabase/docker supabase-docker
    cp -r supabase/utils supabase-docker/utils 2>/dev/null || true
    rm -rf supabase
  fi
  
  cd supabase-docker
  cp .env.example .env
  
  if [ -f "utils/generate-keys.sh" ]; then
    echo "[$(date +%T)] Генерация ключей..." >&3
    bash utils/generate-keys.sh > .env.keys 2>/dev/null
    ANON_KEY=$(grep "^ANON_KEY=" .env.keys | cut -d= -f2- | tr -d '"')
    SERVICE_ROLE_KEY=$(grep "^SERVICE_ROLE_KEY=" .env.keys | cut -d= -f2- | tr -d '"')
    rm -f .env.keys
  else
    ANON_KEY=$(openssl rand -hex 32)
    SERVICE_ROLE_KEY=$(openssl rand -hex 32)
  fi
  
  sed -i "s|^ANON_KEY=.*|ANON_KEY=$ANON_KEY|" .env
  sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY|" .env
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
  [[ -n "$SUPABASE_DOMAIN" ]] && sed -i "s|^PUBLIC_URL=.*|PUBLIC_URL=https://${SUPABASE_DOMAIN}|" .env
  
  echo "[$(date +%T)] Запуск Supabase контейнеров..." >&3
  docker compose -p supabase up -d 2>&1 | while read line; do echo "[$(date +%T)] $line" >&3; done
  sleep 6
  
  echo "[$(date +%T)] Подключение к internal_network..." >&3
  for c in $(docker compose -p supabase ps --format "{{.Names}}" 2>/dev/null); do
    docker network connect internal_network "$c" 2>/dev/null || true
  done
  cd ..
  echo "[$(date +%T)] Supabase готов" >&3
}

generate_compose_file() {
  echo "[$(date +%T)] Генерация docker-compose.yml..." >&3
  cd "$SETUP_DIR"
  
  cat > docker-compose.yml <<'HEADER'
networks:
  internal_network:
    external: true
volumes:
HEADER
  
  [[ " ${SELECTED_ARRAY[*]} " =~ "postgres" ]] && echo "  postgres_data:" >> docker-compose.yml
  [[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]] && echo "  qdrant_storage:" >> docker-compose.yml
  [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && echo "  ollama_data:" >> docker-compose.yml
  [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]] && { echo "  npm_data:"; echo "  npm_letsencrypt:"; } >> docker-compose.yml
  [[ " ${SELECTED_ARRAY[*]} " =~ "portainer" ]] && echo "  portainer_data:" >> docker-compose.yml
  [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]] && echo "  n8n_data:" >> docker-compose.yml
  
  echo "services:" >> docker-compose.yml
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "postgres" ]]; then
    cat >> docker-compose.yml <<EOF
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: ${PGPASSWORD}
      POSTGRES_DB: appdb
    volumes: [postgres_data:/var/lib/postgresql/data]
    networks: [internal_network]
EOF
  fi
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]]; then
    cat >> docker-compose.yml <<EOF
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
EOF
    if [[ "$NPM_ENABLED" -eq 1 && -n "$N8N_DOMAIN" ]]; then
      echo "    # Доступ через NPM: $N8N_DOMAIN" >> docker-compose.yml
    else
      echo "    ports: [\"${N8N_PORT}:5678\"]" >> docker-compose.yml
    fi
    
    cat >> docker-compose.yml <<EOF
    environment:
      N8N_HOST: ${N8N_DOMAIN:-localhost}
      N8N_PORT: 5678
      WEBHOOK_URL: ${N8N_DOMAIN:+https://}${N8N_DOMAIN:-http://localhost}:${N8N_PORT}
EOF
    if [[ "${N8N_DB_POSTGRES:-0}" -eq 1 ]]; then
      cat >> docker-compose.yml <<EOF
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_USER: admin
      DB_POSTGRESDB_PASSWORD: ${PGPASSWORD}
      DB_POSTGRESDB_DATABASE: n8n
EOF
    fi
    cat >> docker-compose.yml <<EOF
    volumes: [n8n_data:/home/node/.n8n]
    networks: [internal_network]
EOF
  fi
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "portainer" ]]; then
    cat >> docker-compose.yml <<EOF
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
EOF
    if [[ "$NPM_ENABLED" -eq 1 && -n "$PORTAINER_DOMAIN" ]]; then
      echo "    # Доступ через NPM: $PORTAINER_DOMAIN" >> docker-compose.yml
    else
      echo "    ports: [\"9000:9000\"]" >> docker-compose.yml
    fi
    cat >> docker-compose.yml <<EOF
    volumes: [/var/run/docker.sock:/var/run/docker.sock, portainer_data:/data]
    networks: [internal_network]
EOF
  fi
  
  for svc in qdrant ollama apache; do
    if [[ " ${SELECTED_ARRAY[*]} " =~ "$svc" ]]; then
      local port_var="${svc^^}_PORT"
      local port="${!port_var}"
      local image="" volumes="" env="" internal_port=""
      
      case "$svc" in
        qdrant) image="qdrant/qdrant:latest"; volumes="qdrant_storage:/qdrant/storage"; internal_port="6333" ;;
        ollama) image="ollama/ollama:latest"; volumes="ollama_data:/root/.ollama"; env="OLLAMA_HOST=0.0.0.0"; internal_port="11434" ;;
        apache) image="httpd:2.4-alpine"; volumes="${APACHE_WWW_PATH}:/usr/local/apache2/htdocs/"; internal_port="80" ;;
      esac
      
      local domain_var="${svc^^}_DOMAIN"
      local domain="${!domain_var}"
      
      cat >> docker-compose.yml <<EOF
  $svc:
    image: $image
    container_name: $svc
    restart: unless-stopped
EOF
      if [[ "$NPM_ENABLED" -eq 1 && -n "$domain" ]]; then
        echo "    # Доступ через NPM: $domain" >> docker-compose.yml
      else
        echo "    ports: [\"${port}:${internal_port}\"]" >> docker-compose.yml
      fi
      [[ -n "$env" ]] && echo "    environment: [$env]" >> docker-compose.yml
      [[ -n "$volumes" ]] && echo "    volumes: [$volumes]" >> docker-compose.yml
      echo "    networks: [internal_network]" >> docker-compose.yml
    fi
  done
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]]; then
    cat >> docker-compose.yml <<'EOF'
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports: ["80:80", "443:443", "81:81"]
    volumes: [npm_data:/data, npm_letsencrypt:/etc/letsencrypt]
    networks: [internal_network]
EOF
  fi
  echo "[$(date +%T)] docker-compose.yml создан" >&3
}

start_containers() {
  echo "[$(date +%T)] Запуск контейнеров..." >&3
  cd "$SETUP_DIR"
  docker compose up -d 2>&1 | while read line; do echo "[$(date +%T)] $line" >&3; done
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && "${N8N_DB_POSTGRES:-0}" -eq 1 ]]; then
    echo "[$(date +%T)] Ожидание PostgreSQL..." >&3
    for i in {1..30}; do
      docker exec postgres pg_isready -U admin &>/dev/null && break
      sleep 2
    done
    docker exec postgres psql -U admin -c "CREATE DATABASE n8n;" 2>/dev/null || true
  fi
  echo "[$(date +%T)] Контейнеры запущены" >&3
}

configure_npm_ssl() {
  [[ "$NPM_ENABLED" -ne 1 || -z "$DOMAIN_MAIN" ]] && return 0
  
  echo "[$(date +%T)] Настройка SSL через NPM API..." >&3
  sleep 12
  
  command -v jq &>/dev/null || { apt-get update -qq >/dev/null && apt-get install -y jq >/dev/null 2>&1; }
  
  local NPM_API="http://localhost:81/api"
  local TOKEN
  TOKEN=$(curl -s -X POST "$NPM_API/tokens" -H "Content-Type: application/json" \
    -d '{"identity":"admin@example.com","secret":"changeme"}' 2>/dev/null | jq -r '.token' 2>/dev/null)
  
  if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
    echo -e "${YELLOW}⚠ NPM API: авторизация не удалась.${NC}" >&3
    return 1
  fi
  
  for svc in n8n apache qdrant ollama portainer supabase; do
    local domain_var="${svc^^}_DOMAIN"
    local domain="${!domain_var}"
    [[ -z "$domain" ]] && continue
    
    local fwd_port=80
    case "$svc" in
      n8n) fwd_port=5678 ;; qdrant) fwd_port=6333 ;; ollama) fwd_port=11434 ;;
      apache) fwd_port=80 ;; portainer) fwd_port=9000 ;; supabase) fwd_port=8000 ;;
    esac
    
    echo "[$(date +%T)] Прокси: $domain → $svc:$fwd_port" >&3
    curl -s -X POST "$NPM_API/nginx/proxy-hosts" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{
        \"domain_names\": [\"$domain\"],
        \"forward_host\": \"$svc\",
        \"forward_port\": $fwd_port,
        \"certificate_id\": \"new\",
        \"meta\": {\"letsencrypt_agree\": true, \"dns_challenge\": false},
        \"ssl_forced\": true,
        \"hsts_enabled\": true,
        \"http2_support\": true
      }" >/dev/null 2>&1
  done
  echo -e "${GREEN}✅ SSL настроен${NC}" >&3
}

full_cleanup() {
  dialog --yesno "⚠️ УДАЛИТЬ ВСЁ?\nКонтейнеры, тома, сети, конфиги из $SETUP_DIR\nДанные будут потеряны!" 12 60 || return 0
  
  echo -e "${YELLOW}🧹 Остановка и удаление...${NC}" >&3
  docker compose -p supabase down -v 2>/dev/null || true
  cd "$SETUP_DIR" 2>/dev/null && docker compose down -v 2>/dev/null || true
  docker system prune -af --volumes 2>/dev/null || true
  rm -rf "$SETUP_DIR" "$STATE_DIR"
  
  dialog --msgbox "✅ Сервер полностью очищен." 8 40
  exit 0
}

reinstall_service() {
  local svc=$1
  cd "$SETUP_DIR" 2>/dev/null || return 1
  case "$svc" in
    supabase) docker compose -p supabase down -v 2>/dev/null; rm -rf supabase-docker; setup_supabase ;;
    *) docker compose stop "$svc" 2>/dev/null; docker compose rm -f "$svc" 2>/dev/null; generate_compose_file; docker compose up -d "$svc" 2>/dev/null ;;
  esac
  dialog --msgbox "✅ $svc переустановлен." 6 40
}

show_summary() {
  local ip=$(hostname -I | awk '{print $1}')
  local msg="✅ УСТАНОВКА ЗАВЕРШЕНА!\n\n"
  msg+="📍 Локальный IP: $ip\n"
  [[ -n "$DOMAIN_MAIN" ]] && msg+="🌐 Основной домен: $DOMAIN_MAIN\n"
  msg+="\n📦 Установленные сервисы:\n"
  for s in "${SELECTED_ARRAY[@]}"; do msg+="  • $s\n"; done
  
  msg+="\n🔐 Учетные данные и секреты:\n"
  [[ -n "$PGPASSWORD" ]] && msg+="  • PostgreSQL: admin / $PGPASSWORD\n"
  [[ -n "$JWT_SECRET" ]] && msg+="  • JWT Secret: $JWT_SECRET\n"
  [[ -n "$LLM_API_KEY" ]] && msg+="  • LLM API Key: ${LLM_API_KEY:0:12}...\n"
  if [[ "$NPM_ENABLED" -eq 1 ]]; then
    msg+="  • NPM Panel: admin@example.com / changeme\n"
  fi
  
  msg+="\n🌐 Доступ к сервисам:\n"
  for svc in n8n portainer apache qdrant ollama supabase; do
    if [[ " ${SELECTED_ARRAY[*]} " =~ "$svc" ]]; then
      local domain_var="${svc^^}_DOMAIN"
      local domain="${!domain_var}"
      local port_var="${svc^^}_PORT"
      local port="${!port_var}"
      
      if [[ "$NPM_ENABLED" -eq 1 && -n "$domain" ]]; then
        msg+="  • $svc: https://$domain\n"
      else
        local p="${port:-default}"
        [[ "$svc" == "n8n" ]] && p="${N8N_PORT:-5678}"
        [[ "$svc" == "portainer" ]] && p="9000"
        [[ "$svc" == "supabase" ]] && p="Studio: 3000 / API: 8000"
        msg+="  • $svc: http://$ip:$p\n"
      fi
    fi
  done
  
  msg+="\n📁 Расположение данных и конфигов:\n"
  msg+="  • Основная директория: $SETUP_DIR\n"
  msg+="  • Состояние установщика: $STATE_DIR\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]] && msg+="  • Сайты Apache: $APACHE_WWW_PATH\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && msg+="  • Supabase Docker: $SETUP_DIR/supabase-docker\n"
  msg+="  • Docker Volumes: /var/lib/docker/volumes/\n"
  msg+="  • Debug лог: $LOG_FILE\n"
  
  msg+="\n💡 Примечания:\n"
  [[ "$NPM_ENABLED" -eq 1 ]] && msg+="  • NPM панель: http://$ip:81 (смените пароль при первом входе)\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && msg+="  • Загрузите модели: docker exec -it ollama ollama pull llama3.1\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && "${N8N_DB_POSTGRES:-0}" -eq 1 ]] && msg+="  • n8n использует PostgreSQL (БД: n8n)\n"
  
  echo -e "$msg" > "$STATE_DIR/summary.txt"
  dialog --title "🎉 Готово (копировать мышкой/Shift+Insert)" --textbox "$STATE_DIR/summary.txt" 24 80
}

# === ОТЛАДОЧНЫЙ прогресс-бар с подробным выводом ===
run_installation_process() {
  {
    echo "5"; echo "### Установка Docker..." >&2; install_docker
    echo "15"; echo "### Настройка сети..." >&2; setup_network
    echo "30"; [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && { echo "### Supabase (может занять 2-5 минут)..." >&2; setup_supabase; }
    echo "60"; echo "### Генерация конфигурации..." >&2; generate_compose_file
    echo "80"; echo "### Запуск контейнеров..." >&2; start_containers
    echo "95"; [[ "$NPM_ENABLED" -eq 1 ]] && { echo "### Настройка SSL..." >&2; configure_npm_ssl; }
    echo "100"; echo "### Завершено!" >&2; sleep 2
  } | dialog --title "🚀 Установка" --gauge "Настройка сервисов...\n\nСмотрите логи: tail -f $LOG_FILE" 12 70 0
}

main() {
  grep -qi "ubuntu\|debian" /etc/os-release || { echo "❌ Только Ubuntu/Debian"; exit 1; }
  [ "$EUID" -eq 0 ] || { echo "❌ Запустите с sudo"; exit 1; }
  command -v dialog &>/dev/null || { apt-get update -qq >/dev/null; apt-get install -y dialog jq >/dev/null 2>&1; }
  
  load_selected; load_params
  [[ "$1" == "--reinstall" && -n "$2" ]] && { reinstall_service "$2"; exit 0; }
  
  case "$(get_state)" in
    start)
      show_service_menu || { save_state "start"; main; return; }
      input_parameters || { show_service_menu || { save_state "start"; main; return; }; }
      run_installation_process
      save_state "completed"
      show_summary
      ;;
    completed)
      dialog --menu "✅ Установка завершена. Действие:" 16 60 5 \
        "1" "➕ Добавить/удалить сервисы" \
        "2" "🔄 Переустановить сервис" \
        "3" "🗑 Полное удаление (WIPE)" \
        "4" "📋 Показать сводку" \
        "5" "🚪 Выйти" 2>"$TEMP_FILE"
      case "$(cat "$TEMP_FILE")" in
        1) show_service_menu; input_parameters; run_installation_process; show_summary ;;
        2)
          local installed=()
          for s in postgres qdrant ollama apache nginx-proxy-manager portainer supabase n8n; do
            docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^$s$" && installed+=("$s" "$s" off)
          done
          [ ${#installed[@]} -eq 0 ] && { dialog --msgbox "Нет активных сервисов." 6 40; exit 0; }
          dialog --checklist "Выберите для переустановки:" 15 50 6 "${installed[@]}" 2>"$TEMP_FILE"
          for s in $(cat "$TEMP_FILE" | tr -d '"'); do reinstall_service "$s"; done ;;
        3) full_cleanup ;;
        4) show_summary ;;
        *) exit 0 ;;
      esac ;;
    *) rm -rf "$STATE_DIR"; save_state "start"; main ;;
  esac
}

main "$@"