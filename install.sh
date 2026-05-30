#!/bin/bash
# Универсальный установщик сервисов v2.2 (FIXED)
# Запуск: см. инструкции ниже

# === === Обработка pipe-запуска (ИСПРАВЛЕНО) === ===
# Используем процессную подстановку вместо cat, чтобы избежать deadlock
if [ ! -t 0 ] && [ -z "$SCRIPT_SELF_EXECUTED" ]; then
  export SCRIPT_SELF_EXECUTED=1
  exec bash <(cat) "$@"
fi

# Отключаем строгий режим для лучшей совместимости с dialog
# set -euo pipefail  # <- закомментировано для отладки

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

cleanup() { rm -f "$TEMP_FILE" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

save_state() { mkdir -p "$STATE_DIR" 2>/dev/null; echo "$1" > "$STATE_FILE"; }
get_state() { [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "start"; }

save_selected_services() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  printf '%s\n' "${SELECTED_ARRAY[@]}" > "$SELECTED_FILE"
}

load_selected_services() {
  SELECTED_ARRAY=()
  # ИСПРАВЛЕНО: фильтр пустых строк + безопасный mapfile
  if [[ -f "$SELECTED_FILE" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && SELECTED_ARRAY+=("$line")
    done < "$SELECTED_FILE"
  fi
}

save_params() {
  mkdir -p "$STATE_DIR" 2>/dev/null
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
  chmod 600 "$PARAMS_FILE" 2>/dev/null || true
}

load_params() {
  [[ -f "$PARAMS_FILE" ]] && source "$PARAMS_FILE"
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
  if command -v ss &>/dev/null && ss -Htuln sport = :$port 2>/dev/null | grep -q .; then
    dialog --title "Ошибка" --msgbox "Порт $port уже занят." 6 50
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

# Подсказка для ввода (Shift+Insert для вставки!)
INPUT_HINT=$'\n[Вставка: Shift+Insert или ПКМ]\n[Копирование: выделить мышью]\n[Tab - навигация]'

# === 1. Меню сервисов ===
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
    --extra-button --extra-label "Выход" --ok-label "Далее" \
    --checklist "Выберите (Пробел=выбор, Enter=далее)$INPUT_HINT" 22 70 10 \
    "${args[@]}" 2>"$TEMP_FILE"
  local res=$?
  [[ $res -eq 1 || $res -eq 3 ]] && return 1
  SELECTED=$(cat "$TEMP_FILE" 2>/dev/null)
  SELECTED_ARRAY=()
  for item in $SELECTED; do
    SELECTED_ARRAY+=("$(echo "$item" | tr -d '"')")
  done
  if [ ${#SELECTED_ARRAY[@]} -eq 0 ]; then
    dialog --msgbox "Выберите хотя бы один сервис." 6 50
    return 1
  fi
  save_selected_services
  return 0
}

# === 2. Параметры ===
step_postgres() {
  dialog --clear --title "Шаг 2: PostgreSQL" \
    --extra-button --extra-label "Назад" --ok-label "Далее" \
    --inputbox "Пароль admin (пусто = авто)$INPUT_HINT" 14 70 "$PGPASSWORD" 2>"$TEMP_FILE"
  local res=$?
  [[ $res -eq 1 || $res -eq 3 ]] && return 1
  PGPASSWORD=$(cat "$TEMP_FILE")
  if [ -z "$PGPASSWORD" ]; then
    PGPASSWORD=$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-20)
    dialog --msgbox "Сгенерирован: $PGPASSWORD" 8 60
  fi
  return 0
}

step_jwt() {
  dialog --clear --title "Шаг 3: JWT Secret" \
    --extra-button --extra-label "Назад" --ok-label "Далее" \
    --inputbox "JWT Secret (пусто = авто)$INPUT_HINT" 14 70 "$JWT_SECRET" 2>"$TEMP_FILE"
  local res=$?
  [[ $res -eq 1 || $res -eq 3 ]] && return 1
  JWT_SECRET=$(cat "$TEMP_FILE")
  [ -z "$JWT_SECRET" ] && JWT_SECRET=$(openssl rand -hex 32)
  return 0
}

step_llm() {
  dialog --clear --title "Шаг 4: LLM" \
    --extra-button --extra-label "Назад" --ok-label "Далее" \
    --radiolist "Провайдер:" 15 60 4 \
    "ollama" "Ollama (локально)" on "openai" "OpenAI" off "anthropic" "Anthropic" off \
    2>"$TEMP_FILE"
  local res=$?
  [[ $res -eq 1 || $res -eq 3 ]] && return 1
  LLM_TYPE=$(cat "$TEMP_FILE")
  case "$LLM_TYPE" in
    openai)
      dialog --extra-button --extra-label "Назад" --ok-label "Далее" \
        --passwordbox "OpenAI API key$INPUT_HINT" 12 70 2>"$TEMP_FILE"
      [[ $? -eq 3 ]] && return 1
      LLM_API_KEY=$(cat "$TEMP_FILE"); LLM_API_URL="https://api.openai.com/v1" ;;
    anthropic)
      dialog --extra-button --extra-label "Назад" --ok-label "Далее" \
        --passwordbox "Anthropic API key$INPUT_HINT" 12 70 2>"$TEMP_FILE"
      [[ $? -eq 3 ]] && return 1
      LLM_API_KEY=$(cat "$TEMP_FILE"); LLM_API_URL="https://api.anthropic.com/v1" ;;
    ollama) LLM_API_URL="http://ollama:11434" ;;
  esac
  return 0
}

step_domain() {
  dialog --clear --title "Шаг 5: Домены" \
    --extra-button --extra-label "Назад" --ok-label "Далее" \
    --form "Домены (можно пусто)$INPUT_HINT" 14 70 0 \
    "Основной:" 1 2 "$DOMAIN" 1 20 40 0 \
    "Supabase:" 3 2 "$SUPABASE_DOMAIN" 3 20 40 0 \
    2>"$TEMP_FILE"
  local res=$?
  [[ $res -eq 1 || $res -eq 3 ]] && return 1
  mapfile -t domains < "$TEMP_FILE"
  DOMAIN="${domains[0]}"; SUPABASE_DOMAIN="${domains[1]}"
  return 0
}

step_ports() {
  while true; do
    local form_args=() row=1
    [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]] && { form_args+=("n8n порт:" $row 2 "$N8N_PORT" $row 20 10 0); ((row+=2)); }
    [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]] && { form_args+=("Apache порт:" $row 2 "$APACHE_HTTP_PORT" $row 20 10 0); ((row+=2)); }
    [[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]] && { form_args+=("Qdrant порт:" $row 2 "$QDRANT_PORT" $row 20 10 0); ((row+=2)); }
    [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && { form_args+=("Ollama порт:" $row 2 "$OLLAMA_PORT" $row 20 10 0); ((row+=2)); }
    [ ${#form_args[@]} -eq 0 ] && break
    local h=$((row+5)); [ $h -gt 20 ] && h=20
    dialog --clear --title "Шаг 6: Порты" \
      --extra-button --extra-label "Назад" --ok-label "Далее" \
      --form "Порты$INPUT_HINT" $h 70 0 "${form_args[@]}" 2>"$TEMP_FILE"
    local res=$?
    [[ $res -eq 1 || $res -eq 3 ]] && return 1
    mapfile -t ports < "$TEMP_FILE"
    local idx=0 ok=true
    [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]] && { N8N_PORT="${ports[$idx]}"; check_port "$N8N_PORT" || ok=false; ((idx++)); }
    [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]] && { APACHE_HTTP_PORT="${ports[$idx]}"; check_port "$APACHE_HTTP_PORT" || ok=false; ((idx++)); }
    [[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]] && { QDRANT_PORT="${ports[$idx]}"; check_port "$QDRANT_PORT" || ok=false; ((idx++)); }
    [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && { OLLAMA_PORT="${ports[$idx]}"; check_port "$OLLAMA_PORT" || ok=false; ((idx++)); }
    $ok && break
  done
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && " ${SELECTED_ARRAY[*]} " =~ "postgres" ]]; then
    dialog --extra-button --extra-label "Назад" --ok-label "Далее" \
      --yesno "n8n: использовать PostgreSQL?" 8 50
    [[ $? -eq 3 ]] && return 1
    [[ $? -eq 0 ]] && N8N_DB_POSTGRES=1 || N8N_DB_POSTGRES=0
  fi
  if [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]]; then
    dialog --extra-button --extra-label "Назад" --ok-label "Далее" \
      --inputbox "Путь для Apache:$INPUT_HINT" 12 70 "$APACHE_WWW_PATH" 2>"$TEMP_FILE"
    [[ $? -eq 3 ]] && return 1
    APACHE_WWW_PATH=$(cat "$TEMP_FILE")
    [ -z "$APACHE_WWW_PATH" ] && APACHE_WWW_PATH="$SETUP_DIR/www"
    APACHE_WWW_PATH=$(realpath -m "$APACHE_WWW_PATH")
    mkdir -p "$APACHE_WWW_PATH" "$APACHE_WWW_PATH/conf"
    [ ! -f "$APACHE_WWW_PATH/index.html" ] && echo "<h1>OK</h1>" > "$APACHE_WWW_PATH/index.html"
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
}

# === 3. Сеть ===
setup_network() {
  docker network inspect internal_network &>/dev/null || docker network create internal_network >/dev/null
  mkdir -p "$SETUP_DIR" && cd "$SETUP_DIR"
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

# === 4. Supabase (FIXED sed + networks) ===
setup_supabase() {
  [[ ! " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && return 0
  cd "$SETUP_DIR"
  if [ ! -d "supabase-docker" ]; then
    git clone --depth 1 --filter=blob:none --sparse https://github.com/supabase/supabase >/dev/null 2>&1
    (cd supabase && git sparse-checkout set docker utils >/dev/null 2>&1)
    mv supabase/docker supabase-docker
    cp -r supabase/utils supabase-docker/utils 2>/dev/null || true
    rm -rf supabase
  fi
  cd supabase-docker
  cp .env.example .env
  if [ -f "utils/generate-keys.sh" ]; then
    bash utils/generate-keys.sh > .env.keys 2>/dev/null
    ANON_KEY=$(grep "^ANON_KEY=" .env.keys | cut -d= -f2- | tr -d '"')
    SERVICE_ROLE_KEY=$(grep "^SERVICE_ROLE_KEY=" .env.keys | cut -d= -f2- | tr -d '"')
    SECRET_KEY_BASE=$(grep "^SECRET_KEY_BASE=" .env.keys | cut -d= -f2- | tr -d '"')
    VAULT_ENC_KEY=$(grep "^VAULT_ENC_KEY=" .env.keys | cut -d= -f2- | tr -d '"')
    rm -f .env.keys
  else
    ANON_KEY=$(openssl rand -hex 32); SERVICE_ROLE_KEY=$(openssl rand -hex 32)
    SECRET_KEY_BASE=$(openssl rand -hex 32); VAULT_ENC_KEY=$(openssl rand -hex 32)
  fi
  PG_META_CRYPTO_KEY=$(openssl rand -hex 32)
  LOGFILE_PUBLIC_ACCESS_TOKEN=$(openssl rand -hex 32)
  LOGFILE_PRIVATE_ACCESS_TOKEN=$(openssl rand -hex 32)
  S3_PROTOCOL_ACCESS_KEY_ID=$(openssl rand -hex 16)
  S3_PROTOCOL_ACCESS_KEY_SECRET=$(openssl rand -hex 32)
  MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
  DASHBOARD_PASSWORD=$(openssl rand -hex 12)
  
  # ИСПРАВЛЕНО: | как разделитель sed + экранирование
  sed -i "s|^ANON_KEY=.*|ANON_KEY=$ANON_KEY|" .env
  sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY|" .env
  sed -i "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$SECRET_KEY_BASE|" .env
  sed -i "s|^VAULT_ENC_KEY=.*|VAULT_ENC_KEY=$VAULT_ENC_KEY|" .env
  sed -i "s|^PG_META_CRYPTO_KEY=.*|PG_META_CRYPTO_KEY=$PG_META_CRYPTO_KEY|" .env
  sed -i "s|^LOGFILE_PUBLIC_ACCESS_TOKEN=.*|LOGFILE_PUBLIC_ACCESS_TOKEN=$LOGFILE_PUBLIC_ACCESS_TOKEN|" .env
  sed -i "s|^LOGFILE_PRIVATE_ACCESS_TOKEN=.*|LOGFILE_PRIVATE_ACCESS_TOKEN=$LOGFILE_PRIVATE_ACCESS_TOKEN|" .env
  sed -i "s|^S3_PROTOCOL_ACCESS_KEY_ID=.*|S3_PROTOCOL_ACCESS_KEY_ID=$S3_PROTOCOL_ACCESS_KEY_ID|" .env
  sed -i "s|^S3_PROTOCOL_ACCESS_KEY_SECRET=.*|S3_PROTOCOL_ACCESS_KEY_SECRET=$S3_PROTOCOL_ACCESS_KEY_SECRET|" .env
  sed -i "s|^MINIO_ROOT_PASSWORD=.*|MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD|" .env
  sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD|" .env
  
  local esc_pass; esc_pass=$(printf '%s\n' "$PGPASSWORD" | sed 's/[&/|]/\\&/g')
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$esc_pass|" .env
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
  if [ -n "$SUPABASE_DOMAIN" ]; then
    sed -i "s|^PUBLIC_URL=.*|PUBLIC_URL=https://${SUPABASE_DOMAIN}|" .env
    sed -i "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://${SUPABASE_DOMAIN}|" .env
    sed -i "s|^SITE_URL=.*|SITE_URL=https://${SUPABASE_DOMAIN}|" .env
  fi
  # Убрано дублирование networks: - подключаем через docker network connect
  
  docker compose -p supabase up -d >/dev/null 2>&1
  sleep 8
  for c in $(docker ps --filter "name=supabase" --format "{{.Names}}" 2>/dev/null); do
    docker network connect internal_network "$c" 2>/dev/null || true
  done
  cd ..
}

# === 5. docker-compose.yml (FIXED YAML + webhook) ===
generate_compose_file() {
  cd "$SETUP_DIR"
  cat > docker-compose.yml <<'YAML_HEADER'
networks:
  internal_network:
    external: true
volumes:
YAML_HEADER
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
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: ${PGPASSWORD}
      POSTGRES_DB: appdb
    volumes: [postgres_data:/var/lib/postgresql/data]
    networks: [internal_network]
EOF

  [[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]] && cat >> docker-compose.yml <<EOF
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    ports: ["${QDRANT_PORT}:6333"]
    volumes: [qdrant_storage:/qdrant/storage]
    networks: [internal_network]
EOF

  [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && cat >> docker-compose.yml <<EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports: ["${OLLAMA_PORT}:11434"]
    environment: [OLLAMA_HOST=0.0.0.0]
    volumes: [ollama_data:/root/.ollama]
    networks: [internal_network]
EOF

  [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]] && cat >> docker-compose.yml <<EOF
  apache:
    image: httpd:2.4-alpine
    container_name: apache
    restart: unless-stopped
    ports: ["${APACHE_HTTP_PORT}:80"]
    volumes:
      - "${APACHE_WWW_PATH}:/usr/local/apache2/htdocs/"
      - "${APACHE_WWW_PATH}/conf:/usr/local/apache2/conf/extra/"
    networks: [internal_network]
EOF

  [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]] && cat >> docker-compose.yml <<EOF
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports: ["80:80","443:443","81:81"]
    volumes: [npm_data:/data,npm_letsencrypt:/etc/letsencrypt]
    networks: [internal_network]
EOF

  [[ " ${SELECTED_ARRAY[*]} " =~ "portainer" ]] && cat >> docker-compose.yml <<EOF
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
    volumes: [/var/run/docker.sock:/var/run/docker.sock,portainer_data:/data]
    ports: ["9000:9000"]
    networks: [internal_network]
EOF

  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]]; then
    cat >> docker-compose.yml <<EOF
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports: ["${N8N_PORT}:5678"]
    environment:
      N8N_HOST: ${DOMAIN:-localhost}
      N8N_PORT: ${N8N_PORT}
      WEBHOOK_URL: ${DOMAIN:+https://}${DOMAIN:-http://localhost}:${N8N_PORT}
EOF
    if [ "${N8N_DB_POSTGRES:-0}" -eq 1 ]; then
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
}

# === 6. Запуск ===
start_containers() {
  cd "$SETUP_DIR"
  docker compose up -d >/dev/null 2>&1
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && "${N8N_DB_POSTGRES:-0}" -eq 1 ]]; then
    for i in {1..30}; do
      docker exec postgres pg_isready -U admin &>/dev/null && break
      sleep 2
    done
    docker exec postgres psql -U admin -c "CREATE DATABASE n8n;" 2>/dev/null || true
  fi
}

# === 7. SSL для NPM (автоматически) ===
configure_npm_ssl() {
  [[ ! " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" || -z "$DOMAIN" ]] && return 0
  echo "### Ожидание NPM..." >&2
  sleep 12
  command -v jq &>/dev/null || { apt-get update -qq >/dev/null && apt-get install -y jq >/dev/null 2>&1; }
  local NPM_API="http://localhost:81/api"
  local TOKEN
  TOKEN=$(curl -s -X POST "$NPM_API/tokens" -H "Content-Type: application/json" \
    -d '{"identity":"admin@example.com","secret":"changeme"}' 2>/dev/null | jq -r '.token' 2>/dev/null)
  if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
    echo -e "${YELLOW}⚠ NPM API: авторизация не удалась. Настройте SSL вручную.${NC}" >&2
    return 1
  fi
  local fwd_host="apache" fwd_port=80
  [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]] && { fwd_host="n8n"; fwd_port=5678; }
  echo "### Создание прокси + SSL для $DOMAIN..." >&2
  local res
  res=$(curl -s -X POST "$NPM_API/nginx/proxy-hosts" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"domain_names\":[\"$DOMAIN\"],\"forward_host\":\"$fwd_host\",\"forward_port\":$fwd_port,\"certificate_id\":\"new\",\"meta\":{\"letsencrypt_agree\":true,\"dns_challenge\":false},\"ssl_forced\":true,\"hsts_enabled\":true,\"http2_support\":true}" 2>/dev/null)
  if echo "$res" | jq -e '.id > 0' &>/dev/null; then
    echo -e "${GREEN}✅ SSL настроен для $DOMAIN${NC}" >&2
  else
    echo -e "${YELLOW}⚠ Ошибка NPM: $(echo "$res" | jq -r '.error.message // "Unknown"')${NC}" >&2
  fi
}

# === 8. Полное удаление (WIPE) ===
full_cleanup() {
  dialog --yesno "⚠️ УДАЛИТЬ ВСЁ: контейнеры, тома, конфиги?\nДанные будут потеряны!" 10 60 || return 0
  echo -e "${YELLOW}🧹 Остановка...${NC}" >&2
  docker compose -p supabase down -v 2>/dev/null || true
  cd "$SETUP_DIR" 2>/dev/null && docker compose down -v 2>/dev/null || true
  echo -e "${YELLOW}🧹 Очистка системы...${NC}" >&2
  docker system prune -af --volumes 2>/dev/null || true
  rm -rf "$SETUP_DIR" "$STATE_DIR"
  dialog --msgbox "✅ Сервер очищен." 8 40
  exit 0
}

# === 9. Переустановка ===
reinstall_service() {
  local svc=$1; cd "$SETUP_DIR" 2>/dev/null || return 1
  case $svc in
    supabase) docker compose -p supabase down -v; rm -rf supabase-docker; setup_supabase ;;
    *) docker compose stop "$svc" 2>/dev/null; docker compose rm -f "$svc" 2>/dev/null; generate_compose_file; docker compose up -d "$svc" ;;
  esac
  dialog --msgbox "$svc переустановлен." 6 40
}

# === 10. Финал ===
show_summary() {
  local ip; ip=$(hostname -I | awk '{print $1}')
  local txt="✅ Готово!\nIP: $ip"
  [[ -n "$DOMAIN" ]] && txt+="\nДомен: $DOMAIN"
  txt+="\n\nPostgres: $PGPASSWORD\nJWT: $JWT_SECRET"
  echo -e "$txt" > "$STATE_DIR/summary.txt"
  dialog --title "Готово (копировать мышкой)" --textbox "$STATE_DIR/summary.txt" 15 60
}

run_installation_process() {
  {
    echo "5"; echo "### Docker..." >&2; install_docker
    echo "15"; echo "### Сеть..." >&2; setup_network
    echo "30"; echo "### Supabase..." >&2; setup_supabase
    echo "60"; echo "### Конфиг..." >&2; generate_compose_file
    echo "80"; echo "### Запуск..." >&2; start_containers
    echo "95"; echo "### SSL..." >&2; configure_npm_ssl
    echo "100"; echo "### Завершено!" >&2; sleep 1
  } | dialog --title "Установка" --gauge "Настройка..." 10 60 0
}

# === ГЛАВНАЯ ===
main() {
  grep -qi "ubuntu\|debian" /etc/os-release || { echo "Только Ubuntu/Debian"; exit 1; }
  [ "$EUID" -eq 0 ] || { echo "Запустите с sudo"; exit 1; }
  command -v dialog &>/dev/null || { apt-get update -qq >/dev/null; apt-get install -y dialog jq >/dev/null 2>&1; }
  
  load_selected_services; load_params
  [[ "$1" == "--reinstall" && -n "$2" ]] && { reinstall_service "$2"; exit 0; }
  
  case "$(get_state)" in
    start)
      show_service_menu || { save_state "start"; main; return; }
      input_parameters || { show_service_menu || { save_state "start"; main; return; }; }
      run_installation_process
      save_state "completed"; show_summary ;;
    completed)
      dialog --menu "Действие:" 14 60 4 \
        "1" "Добавить/удалить сервисы" \
        "2" "Переустановить сервис" \
        "3" "🗑 Полное удаление (WIPE)" \
        "4" "Выйти" 2>"$TEMP_FILE"
      case "$(cat "$TEMP_FILE")" in
        1) show_service_menu; input_parameters; run_installation_process; show_summary ;;
        2)
          local installed=()
          for s in postgres qdrant ollama apache nginx-proxy-manager portainer supabase n8n; do
            docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^$s$" && installed+=("$s" "$s" off)
          done
          [ ${#installed[@]} -eq 0 ] && { dialog --msgbox "Нет сервисов." 6 40; exit 0; }
          dialog --checklist "Выберите:" 15 50 6 "${installed[@]}" 2>"$TEMP_FILE"
          for s in $(cat "$TEMP_FILE" | tr -d '"'); do reinstall_service "$s"; done ;;
        3) full_cleanup ;;
        *) exit 0 ;;
      esac ;;
    *) rm -rf "$STATE_DIR"; save_state "start"; main ;;
  esac
}

main "$@"
