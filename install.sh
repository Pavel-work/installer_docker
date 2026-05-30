#!/bin/bash
# Универсальный установщик сервисов v3.1
# Запуск: curl -fsSL https://raw.githubusercontent.com/Pavel-work/installer_docker/main/install.sh -o install.sh && sudo bash install.sh

# === Обработка pipe-запуска ===
if [ ! -t 0 ] && [ -z "$SCRIPT_SELF_EXECUTED" ]; then
  export SCRIPT_SELF_EXECUTED=1
  exec bash <(cat) "$@"
fi

# Цвета
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

# === Глобальные переменные ===
STATE_DIR="/root/.server-setup-state"
STATE_FILE="$STATE_DIR/state.cfg"
SELECTED_FILE="$STATE_DIR/selected_services.cfg"
PARAMS_FILE="$STATE_DIR/params.env"
SETUP_DIR="/root/server-setup"
TEMP_FILE=$(mktemp)
REAL_USER="${SUDO_USER:-$USER}"

declare -a CREATED_CONTAINERS=()
declare -a CREATED_VOLUMES=()
declare -a CREATED_NETWORKS=()

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
# Auto-generated $(date)
PGPASSWORD=${PGPASSWORD@Q}
JWT_SECRET=${JWT_SECRET@Q}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY@Q}
SUPABASE_SERVICE_KEY=${SUPABASE_SERVICE_KEY@Q}
SUPABASE_DASHBOARD_PASS=${SUPABASE_DASHBOARD_PASS@Q}
LLM_TYPE=${LLM_TYPE@Q}
LLM_API_KEY=${LLM_API_KEY@Q}
LLM_API_URL=${LLM_API_URL@Q}
DOMAIN_MAIN=${DOMAIN_MAIN@Q}
NPM_ENABLED=${NPM_ENABLED@Q}
NPM_ADMIN_EMAIL=${NPM_ADMIN_EMAIL@Q}
NPM_ADMIN_PASS=${NPM_ADMIN_PASS@Q}
POSTGRES_USER=${POSTGRES_USER@Q}
EOF
  # Сохраняем порты и домены для каждого сервиса
  for svc in n8n apache qdrant ollama portainer supabase; do
    local port_var="${svc^^}_PORT"
    local domain_var="${svc^^}_DOMAIN"
    [[ -n "${!port_var:-}" ]] && echo "${port_var}=${!port_var@Q}" >> "$PARAMS_FILE"
    [[ -n "${!domain_var:-}" ]] && echo "${domain_var}=${!domain_var@Q}" >> "$PARAMS_FILE"
  done
  [[ -n "${APACHE_WWW_PATH:-}" ]] && echo "APACHE_WWW_PATH=${APACHE_WWW_PATH@Q}" >> "$PARAMS_FILE"
  [[ -n "${N8N_DB_POSTGRES:-}" ]] && echo "N8N_DB_POSTGRES=${N8N_DB_POSTGRES@Q}" >> "$PARAMS_FILE"
  chmod 600 "$PARAMS_FILE" 2>/dev/null || true
}

load_params() {
  [[ -f "$PARAMS_FILE" ]] && source "$PARAMS_FILE"
  PGPASSWORD="${PGPASSWORD:-}"; JWT_SECRET="${JWT_SECRET:-}"
  SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"; SUPABASE_SERVICE_KEY="${SUPABASE_SERVICE_KEY:-}"
  SUPABASE_DASHBOARD_PASS="${SUPABASE_DASHBOARD_PASS:-}"
  LLM_TYPE="${LLM_TYPE:-ollama}"; LLM_API_KEY="${LLM_API_KEY:-}"
  LLM_API_URL="${LLM_API_URL:-}"; DOMAIN_MAIN="${DOMAIN_MAIN:-}"
  NPM_ENABLED="${NPM_ENABLED:-0}"
  NPM_ADMIN_EMAIL="${NPM_ADMIN_EMAIL:-admin@example.com}"
  NPM_ADMIN_PASS="${NPM_ADMIN_PASS:-changeme}"
  POSTGRES_USER="${POSTGRES_USER:-admin}"
  N8N_PORT="${N8N_PORT:-5678}"; N8N_DOMAIN="${N8N_DOMAIN:-}"
  APACHE_PORT="${APACHE_PORT:-8080}"; APACHE_DOMAIN="${APACHE_DOMAIN:-}"
  APACHE_WWW_PATH="${APACHE_WWW_PATH:-$SETUP_DIR/www}"
  QDRANT_PORT="${QDRANT_PORT:-6333}"; QDRANT_DOMAIN="${QDRANT_DOMAIN:-}"
  OLLAMA_PORT="${OLLAMA_PORT:-11434}"; OLLAMA_DOMAIN="${OLLAMA_DOMAIN:-}"
  PORTAINER_DOMAIN="${PORTAINER_DOMAIN:-}"
  SUPABASE_DOMAIN="${SUPABASE_DOMAIN:-}"
  N8N_DB_POSTGRES="${N8N_DB_POSTGRES:-0}"
}

# === 🔑 Безопасный ввод с поддержкой @file ===
read_with_hint() {
  local prompt="$1" default="$2" var_name="$3" is_password="${4:-0}"
  local hint=$'\n[Shift+Insert или ПКМ для вставки]\n[ИЛИ: @/путь/к/файлу - загрузить из файла]\n[Tab - навигация]'
  
  while true; do
    local dialog_type="--inputbox"
    [[ "$is_password" -eq 1 ]] && dialog_type="--passwordbox"
    dialog --clear --title "Ввод" $dialog_type "$prompt$hint" 16 70 "$default" 2>"$TEMP_FILE"
    local res=$?
    [[ $res -ne 0 ]] && return $res
    local val=$(cat "$TEMP_FILE")
    if [[ "$val" =~ ^@(.+)$ ]]; then
      local fpath="${BASH_REMATCH[1]}"
      if [[ -r "$fpath" ]]; then
        val=$(<"$fpath")
        dialog --msgbox "✅ Загружено из $fpath" 6 50
      else
        dialog --msgbox "❌ Файл не найден: $fpath" 6 50
        continue
      fi
    fi
    eval "$var_name=\$val"
    return 0
  done
}

check_port() {
  local port=$1
  if command -v ss &>/dev/null && ss -Htuln sport = :$port 2>/dev/null | grep -q .; then
    dialog --title "Ошибка" --msgbox "Порт $port занят." 6 40
    return 1
  fi
  return 0
}

install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "### Установка Docker..." >&2
    curl -fsSL https://get.docker.com 2>/dev/null | sh >/dev/null 2>&1
    usermod -aG docker "$REAL_USER" 2>/dev/null || true
    systemctl enable docker --now >/dev/null 2>&1 || true
  fi
  if ! docker compose version &>/dev/null; then
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y docker-compose-plugin >/dev/null 2>&1 || true
  fi
}

# === 1. Выбор сервисов ===
show_service_menu() {
  local args=(
    "postgres" "PostgreSQL (БД)" "off"
    "qdrant" "Qdrant (векторная БД)" "off"
    "ollama" "Ollama (локальные LLM)" "off"
    "apache" "Apache (веб-сервер)" "off"
    "nginx_proxy" "Nginx Proxy Manager (SSL)" "off"
    "portainer" "Portainer (Docker UI)" "off"
    "supabase" "Supabase (BaaS)" "off"
    "n8n" "n8n (автоматизация)" "off"
  )
  if [ ${#SELECTED_ARRAY[@]} -gt 0 ]; then
    for ((i=0; i<${#args[@]}; i+=3)); do
      for sel in "${SELECTED_ARRAY[@]}"; do
        [[ "${args[$i]}" == "$sel" ]] && args[$((i+2))]="on"
      done
    done
  fi
  dialog --clear --title "📦 Шаг 1: Выбор сервисов" \
    --extra-button --extra-label "Выход" --ok-label "Далее ▶" \
    --checklist "Пробел=выбор, Enter=далее" 20 70 10 "${args[@]}" 2>"$TEMP_FILE"
  local res=$?
  [[ $res -eq 1 || $res -eq 3 ]] && return 1
  SELECTED_ARRAY=()
  for item in $(cat "$TEMP_FILE" 2>/dev/null | tr -d '"'); do
    SELECTED_ARRAY+=("$item")
  done
  [[ ${#SELECTED_ARRAY[@]} -eq 0 ]] && { dialog --msgbox "⚠ Выберите хотя бы один сервис." 6 50; return 1; }
  save_selected
  return 0
}

# === 2. Условные параметры ===
input_parameters() {
  POSTGRES_USER="admin"
  
  # Postgres пароль (нужен для postgres/supabase/n8n)
  if [[ " ${SELECTED_ARRAY[*]} " =~ "postgres" || " ${SELECTED_ARRAY[*]} " =~ "supabase" || " ${SELECTED_ARRAY[*]} " =~ "n8n" ]]; then
    while true; do
      read_with_hint "🔐 Пароль PostgreSQL (admin):" "$PGPASSWORD" "PGPASSWORD" 1 || return 1
      [[ -n "$PGPASSWORD" ]] && break
      PGPASSWORD=$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-20)
      dialog --msgbox "🎲 Сгенерирован: $PGPASSWORD" 8 60
      break
    done
  fi
  
  # Supabase (только если выбран)
  if [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]]; then
    read_with_hint "🔑 JWT Secret (пусто = авто):" "$JWT_SECRET" "JWT_SECRET" 1 || return 1
    [[ -z "$JWT_SECRET" ]] && JWT_SECRET=$(openssl rand -hex 32)
    dialog --clear --title "🌐 Supabase" --inputbox "Поддомен Supabase (пусто = без):" 10 70 "$SUPABASE_DOMAIN" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return 1
    SUPABASE_DOMAIN=$(cat "$TEMP_FILE")
  fi
  
  # NPM + домены
  if [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]]; then
    NPM_ENABLED=1
    dialog --clear --title "🌍 Основной домен" --inputbox "Домен (example.com):" 10 70 "$DOMAIN_MAIN" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return 1
    DOMAIN_MAIN=$(cat "$TEMP_FILE")
    
    if [[ -n "$DOMAIN_MAIN" ]]; then
      for svc in n8n apache qdrant ollama portainer supabase; do
        [[ ! " ${SELECTED_ARRAY[*]} " =~ "$svc" ]] && continue
        local default_domain="${svc}.${DOMAIN_MAIN}"
        [[ "$svc" == "nginx_proxy" ]] && continue
        dialog --yesno "🔗 Проксировать $svc с SSL?\nДомен: $default_domain" 10 60 || continue
        local domain_var="${svc^^}_DOMAIN"
        eval "$domain_var=\$default_domain"
      done
    fi
  fi
  
  # Порты (только если NPM не проксирует)
  for svc in n8n apache qdrant ollama; do
    [[ ! " ${SELECTED_ARRAY[*]} " =~ "$svc" ]] && continue
    local port_var="${svc^^}_PORT"
    local domain_var="${svc^^}_DOMAIN"
    # Если NPM проксирует - порт наружу не публикуем
    if [[ "$NPM_ENABLED" -eq 1 && -n "${!domain_var:-}" ]]; then
      continue
    fi
    local default_port=""
    case "$svc" in
      n8n) default_port=5678 ;; apache) default_port=8080 ;;
      qdrant) default_port=6333 ;; ollama) default_port=11434 ;;
    esac
    local current_port="${!port_var:-$default_port}"
    while true; do
      dialog --clear --title "🔌 Порт $svc" --inputbox "Порт для $svc:" 10 70 "$current_port" 2>"$TEMP_FILE"
      [[ $? -ne 0 ]] && return 1
      local new_port=$(cat "$TEMP_FILE")
      check_port "$new_port" && { eval "$port_var=\$new_port"; break; }
    done
  done
  
  # n8n + postgres
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && " ${SELECTED_ARRAY[*]} " =~ "postgres" ]]; then
    dialog --yesno "💾 Использовать PostgreSQL для БД n8n?" 8 50
    [[ $? -eq 0 ]] && N8N_DB_POSTGRES=1 || N8N_DB_POSTGRES=0
  fi
  
  # Apache path
  if [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]]; then
    dialog --clear --title "📁 Путь Apache" --inputbox "Корень сайтов:" 10 70 "$APACHE_WWW_PATH" 2>"$TEMP_FILE"
    [[ $? -eq 0 ]] && {
      APACHE_WWW_PATH=$(cat "$TEMP_FILE")
      [[ -z "$APACHE_WWW_PATH" ]] && APACHE_WWW_PATH="$SETUP_DIR/www"
      APACHE_WWW_PATH=$(realpath -m "$APACHE_WWW_PATH")
      mkdir -p "$APACHE_WWW_PATH" "$APACHE_WWW_PATH/conf"
      [[ ! -f "$APACHE_WWW_PATH/index.html" ]] && echo "<h1>It works!</h1>" > "$APACHE_WWW_PATH/index.html"
    }
  fi
  
  # LLM провайдер
  if [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" || " ${SELECTED_ARRAY[*]} " =~ "supabase" || " ${SELECTED_ARRAY[*]} " =~ "n8n" ]]; then
    dialog --clear --title "🤖 LLM" --radiolist "Провайдер:" 15 60 4 \
      "ollama" "Ollama (локально)" on "openai" "OpenAI" off "anthropic" "Anthropic" off \
      2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return 1
    LLM_TYPE=$(cat "$TEMP_FILE")
    case "$LLM_TYPE" in
      openai|anthropic)
        read_with_hint "🔑 API ключ ($LLM_TYPE):" "" "LLM_API_KEY" 1 || return 1
        [[ "$LLM_TYPE" == "openai" ]] && LLM_API_URL="https://api.openai.com/v1"
        [[ "$LLM_TYPE" == "anthropic" ]] && LLM_API_URL="https://api.anthropic.com/v1"
        ;;
      ollama) LLM_API_URL="http://ollama:11434" ;;
    esac
  fi
  
  save_params
  return 0
}

# === 3. Сеть ===
setup_network() {
  if ! docker network inspect internal_network &>/dev/null; then
    docker network create internal_network >/dev/null
    CREATED_NETWORKS+=("internal_network")
  fi
  mkdir -p "$SETUP_DIR" && cd "$SETUP_DIR"
  cat > .env <<EOF
POSTGRES_PASSWORD=${PGPASSWORD}
POSTGRES_USER=${POSTGRES_USER}
JWT_SECRET=${JWT_SECRET}
EOF
  chmod 600 .env
}

# === 4. Supabase ===
setup_supabase() {
  [[ ! " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && return 0
  cd "$SETUP_DIR"
  if [[ ! -d "supabase-docker" ]]; then
    git clone --depth 1 --filter=blob:none --sparse https://github.com/supabase/supabase >/dev/null 2>&1
    (cd supabase && git sparse-checkout set docker utils >/dev/null 2>&1)
    mv supabase/docker supabase-docker
    cp -r supabase/utils supabase-docker/utils 2>/dev/null || true
    rm -rf supabase
  fi
  cd supabase-docker
  cp .env.example .env
  
  if [[ -f "utils/generate-keys.sh" ]]; then
    bash utils/generate-keys.sh > .env.keys 2>/dev/null
    SUPABASE_ANON_KEY=$(grep "^ANON_KEY=" .env.keys | cut -d= -f2- | tr -d '"')
    SUPABASE_SERVICE_KEY=$(grep "^SERVICE_ROLE_KEY=" .env.keys | cut -d= -f2- | tr -d '"')
    rm -f .env.keys
  else
    SUPABASE_ANON_KEY=$(openssl rand -hex 32)
    SUPABASE_SERVICE_KEY=$(openssl rand -hex 32)
  fi
  
  SUPABASE_DASHBOARD_PASS=$(openssl rand -hex 12)
  
  sed -i "s|^ANON_KEY=.*|ANON_KEY=$SUPABASE_ANON_KEY|" .env
  sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SUPABASE_SERVICE_KEY|" .env
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
  sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$SUPABASE_DASHBOARD_PASS|" .env
  
  local esc_pass; esc_pass=$(printf '%s\n' "$PGPASSWORD" | sed 's/[&/|]/\\&/g')
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$esc_pass|" .env
  
  if [[ -n "$SUPABASE_DOMAIN" ]]; then
    sed -i "s|^PUBLIC_URL=.*|PUBLIC_URL=https://${SUPABASE_DOMAIN}|" .env
    sed -i "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://${SUPABASE_DOMAIN}|" .env
  fi
  
  docker compose -p supabase up -d >/dev/null 2>&1
  
  mapfile -t sb_containers < <(docker compose -p supabase ps --format "{{.Names}}" 2>/dev/null)
  CREATED_CONTAINERS+=("${sb_containers[@]}")
  
  sleep 5
  for c in "${sb_containers[@]}"; do
    docker network connect internal_network "$c" 2>/dev/null || true
  done
  cd ..
}

# === 5. docker-compose.yml ===
generate_compose_file() {
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
  
  [[ " ${SELECTED_ARRAY[*]} " =~ "postgres" ]] && cat >> docker-compose.yml <<EOF
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${PGPASSWORD}
      POSTGRES_DB: appdb
    volumes: [postgres_data:/var/lib/postgresql/data]
    networks: [internal_network]
EOF
  
  [[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]] && {
    local domain="${QDRANT_DOMAIN:-}"
    cat >> docker-compose.yml <<EOF
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
EOF
    if [[ "$NPM_ENABLED" -eq 1 && -n "$domain" ]]; then
      echo "    # Проксируется через NPM: $domain" >> docker-compose.yml
    else
      echo "    ports: [\"${QDRANT_PORT}:6333\"]" >> docker-compose.yml
    fi
    cat >> docker-compose.yml <<EOF
    volumes: [qdrant_storage:/qdrant/storage]
    networks: [internal_network]
EOF
  }
  
  [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && {
    local domain="${OLLAMA_DOMAIN:-}"
    cat >> docker-compose.yml <<EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    environment: [OLLAMA_HOST=0.0.0.0]
EOF
    if [[ "$NPM_ENABLED" -eq 1 && -n "$domain" ]]; then
      echo "    # Проксируется через NPM: $domain" >> docker-compose.yml
    else
      echo "    ports: [\"${OLLAMA_PORT}:11434\"]" >> docker-compose.yml
    fi
    cat >> docker-compose.yml <<EOF
    volumes: [ollama_data:/root/.ollama]
    networks: [internal_network]
EOF
  }
  
  [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]] && {
    local domain="${APACHE_DOMAIN:-}"
    cat >> docker-compose.yml <<EOF
  apache:
    image: httpd:2.4-alpine
    container_name: apache
    restart: unless-stopped
EOF
    if [[ "$NPM_ENABLED" -eq 1 && -n "$domain" ]]; then
      echo "    # Проксируется через NPM: $domain" >> docker-compose.yml
    else
      echo "    ports: [\"${APACHE_PORT}:80\"]" >> docker-compose.yml
    fi
    cat >> docker-compose.yml <<EOF
    volumes:
      - "${APACHE_WWW_PATH}:/usr/local/apache2/htdocs/"
      - "${APACHE_WWW_PATH}/conf:/usr/local/apache2/conf/extra/"
    networks: [internal_network]
EOF
  }
  
  [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]] && cat >> docker-compose.yml <<EOF
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports: ["80:80", "443:443", "81:81"]
    volumes: [npm_data:/data, npm_letsencrypt:/etc/letsencrypt]
    networks: [internal_network]
EOF
  
  [[ " ${SELECTED_ARRAY[*]} " =~ "portainer" ]] && {
    local domain="${PORTAINER_DOMAIN:-}"
    cat >> docker-compose.yml <<EOF
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
EOF
    if [[ "$NPM_ENABLED" -eq 1 && -n "$domain" ]]; then
      echo "    # Проксируется через NPM: $domain" >> docker-compose.yml
    else
      echo "    ports: [\"9000:9000\"]" >> docker-compose.yml
    fi
    cat >> docker-compose.yml <<EOF
    volumes: [/var/run/docker.sock:/var/run/docker.sock, portainer_data:/data]
    networks: [internal_network]
EOF
  }
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]]; then
    local domain="${N8N_DOMAIN:-}"
    cat >> docker-compose.yml <<EOF
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
EOF
    if [[ "$NPM_ENABLED" -eq 1 && -n "$domain" ]]; then
      echo "    # Проксируется через NPM: $domain" >> docker-compose.yml
    else
      echo "    ports: [\"${N8N_PORT}:5678\"]" >> docker-compose.yml
    fi
    cat >> docker-compose.yml <<EOF
    environment:
      N8N_HOST: ${domain:-localhost}
      N8N_PORT: 5678
      WEBHOOK_URL: ${domain:+https://}${domain:-http://localhost}${domain:+:443}${domain:-:${N8N_PORT}}
EOF
    if [[ "${N8N_DB_POSTGRES:-0}" -eq 1 ]]; then
      cat >> docker-compose.yml <<EOF
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${PGPASSWORD}
      DB_POSTGRESDB_DATABASE: n8n
EOF
    fi
    cat >> docker-compose.yml <<EOF
    volumes: [n8n_data:/home/node/.n8n]
    networks: [internal_network]
EOF
  fi
}

# === 6. Запуск ===
start_containers() {
  cd "$SETUP_DIR"
  docker compose up -d >/dev/null 2>&1
  # Сохраняем список созданных контейнеров
  mapfile -t main_containers < <(docker compose ps --format "{{.Names}}" 2>/dev/null)
  CREATED_CONTAINERS+=("${main_containers[@]}")
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && "${N8N_DB_POSTGRES:-0}" -eq 1 ]]; then
    for i in {1..30}; do
      docker exec postgres pg_isready -U "$POSTGRES_USER" &>/dev/null && break
      sleep 2
    done
    docker exec postgres psql -U "$POSTGRES_USER" -c "CREATE DATABASE n8n;" 2>/dev/null || true
  fi
}

# === 7. SSL ===
configure_npm_ssl() {
  [[ "$NPM_ENABLED" -ne 1 || -z "$DOMAIN_MAIN" ]] && return 0
  echo "### Настройка SSL..." >&2
  sleep 12
  command -v jq &>/dev/null || { apt-get update -qq >/dev/null && apt-get install -y jq >/dev/null 2>&1; }
  
  local NPM_API="http://localhost:81/api"
  local TOKEN
  TOKEN=$(curl -s -X POST "$NPM_API/tokens" -H "Content-Type: application/json" \
    -d "{\"identity\":\"$NPM_ADMIN_EMAIL\",\"secret\":\"$NPM_ADMIN_PASS\"}" 2>/dev/null | jq -r '.token' 2>/dev/null)
  
  if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
    echo -e "${YELLOW}⚠ NPM API: настройте SSL вручную в панели :81${NC}" >&2
    return 1
  fi
  
  for svc in n8n apache qdrant ollama portainer supabase; do
    local domain_var="${svc^^}_DOMAIN"
    local domain="${!domain_var:-}"
    [[ -z "$domain" ]] && continue
    local fwd_host="$svc" fwd_port=80
    case "$svc" in
      n8n) fwd_port=5678 ;; qdrant) fwd_port=6333 ;; ollama) fwd_port=11434 ;;
      apache) fwd_port=80 ;; portainer) fwd_port=9000 ;;
      supabase) fwd_host="supabase-kong"; fwd_port=8000 ;;
    esac
    curl -s -X POST "$NPM_API/nginx/proxy-hosts" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"domain_names\":[\"$domain\"],\"forward_host\":\"$fwd_host\",\"forward_port\":$fwd_port,\"certificate_id\":\"new\",\"meta\":{\"letsencrypt_agree\":true,\"dns_challenge\":false},\"ssl_forced\":true,\"hsts_enabled\":true,\"http2_support\":true}" >/dev/null 2>&1
  done
  echo -e "${GREEN}✅ SSL настроен${NC}" >&2
}

# === 8. Полное удаление ===
full_cleanup() {
  dialog --yesno "⚠️ УДАЛИТЬ ВСЁ?\nКонтейнеры, тома, сети, конфиги.\nДанные будут потеряны!" 12 60 || return 0
  echo -e "${YELLOW}🧹 Остановка...${NC}" >&2
  docker compose -p supabase down -v 2>/dev/null || true
  cd "$SETUP_DIR" 2>/dev/null && docker compose down -v 2>/dev/null || true
  for c in "${CREATED_CONTAINERS[@]}"; do docker rm -f "$c" 2>/dev/null || true; done
  for v in "${CREATED_VOLUMES[@]}"; do docker volume rm "$v" 2>/dev/null || true; done
  for n in "${CREATED_NETWORKS[@]}"; do docker network rm "$n" 2>/dev/null || true; done
  docker system prune -af --volumes 2>/dev/null || true
  rm -rf "$SETUP_DIR" "$STATE_DIR"
  dialog --msgbox "✅ Сервер очищен." 8 40
  exit 0
}

reinstall_service() {
  local svc=$1; cd "$SETUP_DIR" 2>/dev/null || return 1
  case "$svc" in
    supabase) docker compose -p supabase down -v 2>/dev/null; rm -rf supabase-docker; setup_supabase ;;
    *) docker compose stop "$svc" 2>/dev/null; docker compose rm -f "$svc" 2>/dev/null; generate_compose_file; docker compose up -d "$svc" 2>/dev/null ;;
  esac
  dialog --msgbox "✅ $svc переустановлен." 6 40
}

# === 🎯 9. ДЕТАЛИЗИРОВАННАЯ СВОДКА ===
show_summary() {
  local ip=$(hostname -I | awk '{print $1}')
  local external_ip=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "не определён")
  
  local summary_file="$STATE_DIR/summary.txt"
  
  {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           ✅ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 СЕТЬ И ДОСТУП"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Локальный IP:  $ip"
    echo "  Внешний IP:    $external_ip"
    [[ -n "$DOMAIN_MAIN" ]] && echo "  Домен:         $DOMAIN_MAIN"
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 УСТАНОВЛЕННЫЕ СЕРВИСЫ"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # PostgreSQL
    if [[ " ${SELECTED_ARRAY[*]} " =~ "postgres" ]]; then
      echo ""
      echo "🐘 PostgreSQL"
      echo "  ├─ Контейнер:  postgres"
      echo "  ├─ Пользователь: ${POSTGRES_USER}"
      echo "  ├─ Пароль:     ${PGPASSWORD}"
      echo "  ├─ БД:         appdb"
      [[ "${N8N_DB_POSTGRES:-0}" -eq 1 ]] && echo "  ├─ БД n8n:     n8n"
      echo "  ├─ Порт:       5432 (только внутри сети)"
      echo "  └─ Volume:     postgres_data:/var/lib/postgresql/data"
    fi
    
    # n8n
    if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]]; then
      echo ""
      echo "🤖 n8n (автоматизация)"
      echo "  ├─ Контейнер:  n8n"
      if [[ -n "${N8N_DOMAIN:-}" ]]; then
        echo "  ├─ URL:        https://${N8N_DOMAIN}"
      else
        echo "  ├─ URL:        http://$ip:${N8N_PORT}"
      fi
      echo "  ├─ Порт:       ${N8N_PORT}"
      echo "  ├─ БД:         $([ "${N8N_DB_POSTGRES:-0}" -eq 1 ] && echo "PostgreSQL (n8n)" || echo "SQLite (встроенная)")"
      echo "  └─ Volume:     n8n_data:/home/node/.n8n"
    fi
    
    # Portainer
    if [[ " ${SELECTED_ARRAY[*]} " =~ "portainer" ]]; then
      echo ""
      echo "🎛  Portainer (Docker UI)"
      echo "  ├─ Контейнер:  portainer"
      if [[ -n "${PORTAINER_DOMAIN:-}" ]]; then
        echo "  ├─ URL:        https://${PORTAINER_DOMAIN}"
      else
        echo "  ├─ URL:        http://$ip:9000"
      fi
      echo "  ├─ Порт:       9000"
      echo "  └─ Volume:     portainer_data:/data"
    fi
    
    # Nginx Proxy Manager
    if [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]]; then
      echo ""
      echo "🔐 Nginx Proxy Manager"
      echo "  ├─ Контейнер:  nginx-proxy-manager"
      echo "  ├─ Admin UI:   http://$ip:81"
      echo "  ├─ Логин:      $NPM_ADMIN_EMAIL"
      echo "  ├─ Пароль:     $NPM_ADMIN_PASS"
      echo "  │              ⚠ СМЕНИТЕ ПРИ ПЕРВОМ ВХОДЕ!"
      echo "  ├─ Порты:      80 (HTTP), 443 (HTTPS), 81 (Admin)"
      echo "  └─ Volumes:    npm_data:/data, npm_letsencrypt:/etc/letsencrypt"
    fi
    
    # Supabase
    if [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]]; then
      echo ""
      echo "⚡ Supabase (BaaS)"
      echo "  ├─ Проект:     supabase (отдельный compose)"
      if [[ -n "${SUPABASE_DOMAIN:-}" ]]; then
        echo "  ├─ URL:        https://${SUPABASE_DOMAIN}"
      else
        echo "  ├─ URL:        http://$ip:8000 (Kong API)"
      fi
      echo "  ├─ Studio:     http://$ip:3000 (если опубликован)"
      echo "  ├─ Dashboard пароль: ${SUPABASE_DASHBOARD_PASS}"
      echo "  ├─ JWT Secret: $JWT_SECRET"
      echo "  ├─ ANON_KEY:   ${SUPABASE_ANON_KEY:0:32}..."
      echo "  ├─ SERVICE_KEY: ${SUPABASE_SERVICE_KEY:0:32}..."
      echo "  └─ Каталог:    $SETUP_DIR/supabase-docker"
    fi
    
    # Qdrant
    if [[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]]; then
      echo ""
      echo "🔷 Qdrant (векторная БД)"
      echo "  ├─ Контейнер:  qdrant"
      if [[ -n "${QDRANT_DOMAIN:-}" ]]; then
        echo "  ├─ URL:        https://${QDRANT_DOMAIN}"
      else
        echo "  ├─ URL:        http://$ip:${QDRANT_PORT}"
      fi
      echo "  ├─ Порт:       ${QDRANT_PORT}"
      echo "  └─ Volume:     qdrant_storage:/qdrant/storage"
    fi
    
    # Ollama
    if [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]]; then
      echo ""
      echo "🧠 Ollama (локальные LLM)"
      echo "  ├─ Контейнер:  ollama"
      if [[ -n "${OLLAMA_DOMAIN:-}" ]]; then
        echo "  ├─ URL:        https://${OLLAMA_DOMAIN}"
      else
        echo "  ├─ URL:        http://$ip:${OLLAMA_PORT}"
      fi
      echo "  ├─ Порт:       ${OLLAMA_PORT}"
      echo "  ├─ Volume:     ollama_data:/root/.ollama"
      echo "  └─ Команды:"
      echo "      docker exec -it ollama ollama pull llama3.1"
      echo "      docker exec -it ollama ollama pull nomic-embed-text"
    fi
    
    # Apache
    if [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]]; then
      echo ""
      echo "🌐 Apache (веб-сервер)"
      echo "  ├─ Контейнер:  apache"
      if [[ -n "${APACHE_DOMAIN:-}" ]]; then
        echo "  ├─ URL:        https://${APACHE_DOMAIN}"
      else
        echo "  ├─ URL:        http://$ip:${APACHE_PORT}"
      fi
      echo "  ├─ Порт:       ${APACHE_PORT}"
      echo "  ├─ Корень:     ${APACHE_WWW_PATH}"
      echo "  └─ Конфиг:     ${APACHE_WWW_PATH}/conf"
    fi
    
    # LLM
    if [[ -n "${LLM_TYPE:-}" && "$LLM_TYPE" != "ollama" ]]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "🤖 LLM ПРОВАЙДЕР"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  Провайдер:     ${LLM_TYPE^^}"
      echo "  API URL:       ${LLM_API_URL}"
      echo "  API Key:       ${LLM_API_KEY:0:10}...${LLM_API_KEY: -4}"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📁 ФАЙЛОВАЯ СТРУКТУРА"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Каталог установки:  $SETUP_DIR"
    echo "  ├─ docker-compose.yml  (основные сервисы)"
    echo "  ├─ .env                (переменные окружения)"
    [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && echo "  ├─ supabase-docker/    (отдельный проект Supabase)"
    [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]] && echo "  └─ ${APACHE_WWW_PATH}  (сайты Apache)"
    echo ""
    echo "  Конфигурация:         $STATE_DIR"
    echo "  ├─ params.env          (пароли, параметры)"
    echo "  ├─ selected_services.cfg"
    echo "  └─ summary.txt         (этот файл)"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🛠 ПОЛЕЗНЫЕ КОМАНДЫ"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Просмотр логов:       docker compose -f $SETUP_DIR/docker-compose.yml logs -f"
    echo "  Логи Supabase:        docker compose -p supabase logs -f"
    echo "  Перезапуск:           cd $SETUP_DIR && docker compose restart"
    echo "  Остановка всего:      cd $SETUP_DIR && docker compose down"
    echo "  Добавить в автозагрузку: systemctl enable docker"
    echo ""
    echo "  Повторный запуск установщика:"
    echo "    sudo bash $SETUP_DIR/../install.sh  (или скачать заново)"
    echo ""
    echo "  Полное удаление (WIPE):"
    echo "    sudo bash install.sh → выбрать пункт '3' в меню"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  ВАЖНЫЕ ЗАМЕЧАНИЯ"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]] && echo "  • Смените пароль NPM при первом входе (admin@example.com)"
    [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && echo "  • Загрузите модели Ollama: docker exec -it ollama ollama pull llama3.1"
    [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && echo "  • Supabase использует свой docker-compose (проект 'supabase')"
    [[ "$NPM_ENABLED" -eq 1 && -n "$DOMAIN_MAIN" ]] && echo "  • Убедитесь, что DNS A-записи указывают на $external_ip"
    echo "  • Сохраните этот файл: cat $summary_file"
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          🎉 УДАЧНОЙ РАБОТЫ С ВАШИМИ СЕРВИСАМИ!              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
  } | tee "$summary_file"
  
  # Показываем в dialog тоже
  dialog --title "📋 Итоговая сводка" --textbox "$summary_file" 30 80
}

run_installation_process() {
  {
    echo "5"; echo "### Docker..." >&2; install_docker
    echo "15"; echo "### Сеть..." >&2; setup_network
    echo "30"; [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && { echo "### Supabase..." >&2; setup_supabase; }
    echo "60"; echo "### Конфиг..." >&2; generate_compose_file
    echo "80"; echo "### Запуск..." >&2; start_containers
    echo "95"; [[ "$NPM_ENABLED" -eq 1 ]] && { echo "### SSL..." >&2; configure_npm_ssl; }
    echo "100"; echo "### Готово!" >&2; sleep 1
  } | dialog --title "🚀 Установка" --gauge "Настройка сервисов..." 10 60 0
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
      dialog --menu "✅ Установка завершена. Действие:" 18 60 6 \
        "1" "➕ Добавить/удалить сервисы" \
        "2" "🔄 Переустановить сервис" \
        "3" "🗑 Полное удаление (WIPE)" \
        "4" "📋 Показать сводку снова" \
        "5" "💾 Сохранить сводку в /root" \
        "6" "🚪 Выйти" 2>"$TEMP_FILE"
      case "$(cat "$TEMP_FILE")" in
        1) show_service_menu; input_parameters; run_installation_process; show_summary ;;
        2)
          local installed=()
          for s in postgres qdrant ollama apache nginx-proxy-manager portainer supabase n8n; do
            docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^$s$" && installed+=("$s" "$s" off)
          done
          [ ${#installed[@]} -eq 0 ] && { dialog --msgbox "Нет активных сервисов." 6 40; exit 0; }
          dialog --checklist "Выберите для переустановки:" 15 50 6 "${installed[@]}" 2>"$TEMP_FILE"
          for s in $(cat "$TEMP_FILE" | tr -d '"'); do reinstall_service "$s"; done
          ;;
        3) full_cleanup ;;
        4) show_summary ;;
        5) cp "$STATE_DIR/summary.txt" /root/install-summary.txt && dialog --msgbox "✅ Сохранено в /root/install-summary.txt" 6 50 ;;
        *) exit 0 ;;
      esac
      ;;
    *) rm -rf "$STATE_DIR"; save_state "start"; main ;;
  esac
}

main "$@"
