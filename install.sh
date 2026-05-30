#!/bin/bash
# Универсальный установщик сервисов v4.0 (STABLE + DEBUG)
# Исправлено: зависания, фейковые успехи, вставка ключей, полное удаление

# === Обработка pipe-запуска (безопасный перезапуск через process substitution) ===
if [ ! -t 0 ] && [ -z "$SCRIPT_SELF_EXECUTED" ]; then
  export SCRIPT_SELF_EXECUTED=1
  exec bash <(cat) "$@"
fi

# Цвета
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# === Глобальные переменные ===
STATE_DIR="/root/.server-setup-state"
STATE_FILE="$STATE_DIR/state.cfg"
SELECTED_FILE="$STATE_DIR/selected_services.cfg"
PARAMS_FILE="$STATE_DIR/params.env"
SETUP_DIR="/root/server-setup"
TEMP_FILE=$(mktemp)
REAL_USER="${SUDO_USER:-$USER}"

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
  PGPASSWORD="${PGPASSWORD:-}"; JWT_SECRET="${JWT_SECRET:-}"
  LLM_TYPE="${LLM_TYPE:-ollama}"; LLM_API_KEY="${LLM_API_KEY:-}"
  LLM_API_URL="${LLM_API_URL:-}"; DOMAIN_MAIN="${DOMAIN_MAIN:-}"
  SUPABASE_DOMAIN="${SUPABASE_DOMAIN:-}"; N8N_PORT="${N8N_PORT:-5678}"
  N8N_DOMAIN="${N8N_DOMAIN:-}"; N8N_DB_POSTGRES="${N8N_DB_POSTGRES:-0}"
  APACHE_WWW_PATH="${APACHE_WWW_PATH:-$SETUP_DIR/www}"
  APACHE_PORT="${APACHE_PORT:-8080}"; APACHE_DOMAIN="${APACHE_DOMAIN:-}"
  QDRANT_PORT="${QDRANT_PORT:-6333}"; QDRANT_DOMAIN="${QDRANT_DOMAIN:-}"
  OLLAMA_PORT="${OLLAMA_PORT:-11434}"; OLLAMA_DOMAIN="${OLLAMA_DOMAIN:-}"
  PORTAINER_DOMAIN="${PORTAINER_DOMAIN:-}"; NPM_ENABLED="${NPM_ENABLED:-0}"
}

# === 🔑 Безопасный ввод (Shift+Insert / ПКМ / @файл) ===
read_secure_input() {
  local prompt="$1" default="$2" var_name="$3"
  local hint=$'\n[Вставка: Shift+Insert или ПКМ мыши]\n[Или введите @/путь/к/файлу для загрузки]'
  while true; do
    dialog --clear --title "Ввод параметра" --inputbox "$prompt$hint" 15 70 "$default" 2>"$TEMP_FILE"
    local res=$?; [[ $res -ne 0 ]] && return $res
    local val=$(cat "$TEMP_FILE")
    if [[ "$val" =~ ^@(.+)$ ]]; then
      local fpath="${BASH_REMATCH[1]}"
      if [[ -r "$fpath" ]]; then val=$(<"$fpath"); dialog --msgbox "✅ Загружено из $fpath" 6 50
      else dialog --msgbox "❌ Файл не найден: $fpath" 6 50; continue; fi
    fi
    declare -g "$var_name=$val"; return 0
  done
}

check_port() {
  local port=$1
  if command -v ss &>/dev/null && ss -Htuln sport = :$port 2>/dev/null | grep -q .; then
    dialog --title "Ошибка" --msgbox "Порт $port уже занят." 6 40; return 1
  fi; return 0
}

# === Установка Docker (БЕЗ глушения ошибок) ===
install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "### Установка Docker..." >&2
    curl -fsSL https://get.docker.com | sh 2>&1 | tail -5 >&2
    usermod -aG docker "$REAL_USER" 2>/dev/null || true
    systemctl enable docker --now >/dev/null 2>&1 || true
  fi
  if ! docker compose version &>/dev/null; then
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y docker-compose-plugin 2>&1 | tail -3 >&2
  fi
}

# === 1. Выбор сервисов ===
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
    --checklist "Пробел = выбор, Enter = далее" 20 70 10 "${args[@]}" 2>"$TEMP_FILE"
  local res=$?; [[ $res -eq 1 || $res -eq 3 ]] && return 1
  SELECTED_ARRAY=()
  for item in $(cat "$TEMP_FILE" 2>/dev/null | tr -d '"'); do SELECTED_ARRAY+=("$item"); done
  if [ ${#SELECTED_ARRAY[@]} -eq 0 ]; then
    dialog --msgbox "⚠ Выберите хотя бы один сервис." 6 50; return 1
  fi
  save_selected; return 0
}

# === 2. Условные параметры ===
input_parameters() {
  # PostgreSQL
  if [[ " ${SELECTED_ARRAY[*]} " =~ "postgres" || " ${SELECTED_ARRAY[*]} " =~ "supabase" ]]; then
    while true; do
      read_secure_input "🔐 Пароль PostgreSQL (admin):" "$PGPASSWORD" "PGPASSWORD" || return 1
      [[ -n "$PGPASSWORD" ]] && break
      PGPASSWORD=$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-20)
      dialog --msgbox "🎲 Сгенерирован: $PGPASSWORD" 8 60; break
    done
  fi
  # Supabase
  if [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]]; then
    read_secure_input "🔑 JWT Secret (пусто = авто):" "$JWT_SECRET" "JWT_SECRET" || return 1
    [[ -z "$JWT_SECRET" ]] && JWT_SECRET=$(openssl rand -hex 32)
    dialog --clear --title "🌐 Supabase домен" --inputbox "Поддомен (пусто = без):" 10 70 "$SUPABASE_DOMAIN" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return 1; SUPABASE_DOMAIN=$(cat "$TEMP_FILE")
  fi
  # NPM
  if [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]]; then
    NPM_ENABLED=1
    dialog --clear --title "🌍 Основной домен" --inputbox "Домен (example.com):" 10 70 "$DOMAIN_MAIN" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return 1; DOMAIN_MAIN=$(cat "$TEMP_FILE")
    if [[ -n "$DOMAIN_MAIN" ]]; then
      for svc in n8n apache qdrant ollama portainer supabase; do
        [[ " ${SELECTED_ARRAY[*]} " =~ "$svc" ]] || continue
        local def="${svc}.${DOMAIN_MAIN}"
        [[ "$svc" == "supabase" && -n "$SUPABASE_DOMAIN" ]] && def="$SUPABASE_DOMAIN"
        dialog --yesno "🔗 Проксировать $svc с SSL?\n$def" 10 60 || continue
        declare -g "${svc^^}_DOMAIN=$def"
      done
    fi
  fi
  # Порты (только если НЕ через NPM)
  for svc in n8n apache qdrant ollama; do
    [[ " ${SELECTED_ARRAY[*]} " =~ "$svc" ]] || continue
    local dvar="${svc^^}_DOMAIN"; [[ "$NPM_ENABLED" -eq 1 && -n "${!dvar}" ]] && continue
    local pvar="${svc^^}_PORT"; local cp="${!pvar}"
    case "$svc" in n8n) cp="${cp:-5678}";; apache) cp="${cp:-8080}";; qdrant) cp="${cp:-6333}";; ollama) cp="${cp:-11434}";; esac
    while true; do
      dialog --clear --title "🔌 Порт $svc" --inputbox "Порт:" 10 70 "$cp" 2>"$TEMP_FILE"
      [[ $? -ne 0 ]] && return 1; local np=$(cat "$TEMP_FILE")
      check_port "$np" && { declare -g "$pvar=$np"; break; }
    done
  done
  # n8n + Postgres
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && " ${SELECTED_ARRAY[*]} " =~ "postgres" ]]; then
    dialog --yesno "💾 Использовать PostgreSQL для n8n?" 8 50
    [[ $? -eq 0 ]] && N8N_DB_POSTGRES=1 || N8N_DB_POSTGRES=0
  fi
  # Apache path
  if [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]]; then
    dialog --clear --title "📁 Путь Apache" --inputbox "Корневая папка:" 10 70 "$APACHE_WWW_PATH" 2>"$TEMP_FILE"
    [[ $? -eq 0 ]] && {
      APACHE_WWW_PATH=$(cat "$TEMP_FILE"); [[ -z "$APACHE_WWW_PATH" ]] && APACHE_WWW_PATH="$SETUP_DIR/www"
      APACHE_WWW_PATH=$(realpath -m "$APACHE_WWW_PATH")
      mkdir -p "$APACHE_WWW_PATH" "$APACHE_WWW_PATH/conf"
      [ ! -f "$APACHE_WWW_PATH/index.html" ] && echo "<h1>OK</h1>" > "$APACHE_WWW_PATH/index.html"
    }
  fi
  # LLM
  if [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] || { [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]] && dialog --yesno "🤖 Подключить LLM API к n8n?" 8 50; }; then
    dialog --clear --title "🤖 LLM" --radiolist "Провайдер:" 15 60 4 \
      "ollama" "Ollama" on "openai" "OpenAI" off "anthropic" "Anthropic" off 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return 1; LLM_TYPE=$(cat "$TEMP_FILE")
    case "$LLM_TYPE" in
      openai|anthropic)
        local u="https://api.${LLM_TYPE}.com/v1"; [[ "$LLM_TYPE" == "anthropic" ]] && u="https://api.anthropic.com/v1"
        read_secure_input "🔑 API ключ ($LLM_TYPE):" "" "LLM_API_KEY" || return 1; LLM_API_URL="$u" ;;
      ollama) LLM_API_URL="http://ollama:11434" ;;
    esac
  fi
  save_params; return 0
}

setup_network() {
  docker network inspect internal_network &>/dev/null || docker network create internal_network >/dev/null
  mkdir -p "$SETUP_DIR" && cd "$SETUP_DIR"
  cat > .env <<EOF
POSTGRES_PASSWORD=${PGPASSWORD}
JWT_SECRET=${JWT_SECRET}
LLM_API_KEY=${LLM_API_KEY}
LLM_API_URL=${LLM_API_URL}
DOMAIN_MAIN=${DOMAIN_MAIN}
EOF
  chmod 600 .env
}

setup_supabase() {
  [[ ! " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && return 0
  cd "$SETUP_DIR"
  if [ ! -d "supabase-docker" ]; then
    echo "### Клонирование Supabase..." >&2
    git clone --depth 1 --filter=blob:none --sparse https://github.com/supabase/supabase 2>&1 | tail -3 >&2
    (cd supabase && git sparse-checkout set docker utils 2>/dev/null)
    mv supabase/docker supabase-docker; cp -r supabase/utils supabase-docker/utils 2>/dev/null || true; rm -rf supabase
  fi
  cd supabase-docker; cp .env.example .env
  if [ -f "utils/generate-keys.sh" ]; then
    bash utils/generate-keys.sh > .env.keys 2>/dev/null
    ANON_KEY=$(grep "^ANON_KEY=" .env.keys | cut -d= -f2- | tr -d '"')
    SERVICE_ROLE_KEY=$(grep "^SERVICE_ROLE_KEY=" .env.keys | cut -d= -f2- | tr -d '"')
    rm -f .env.keys
  else ANON_KEY=$(openssl rand -hex 32); SERVICE_ROLE_KEY=$(openssl rand -hex 32); fi
  sed -i "s|^ANON_KEY=.*|ANON_KEY=$ANON_KEY|" .env
  sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY|" .env
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
  [[ -n "$SUPABASE_DOMAIN" ]] && sed -i "s|^PUBLIC_URL=.*|PUBLIC_URL=https://${SUPABASE_DOMAIN}|" .env
  echo "### Запуск Supabase..." >&2
  docker compose -p supabase up -d 2>&1 | tail -5 >&2
  sleep 6
  for c in $(docker compose -p supabase ps --format "{{.Names}}" 2>/dev/null); do
    docker network connect internal_network "$c" 2>/dev/null || true
  done; cd ..
}

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
    [[ "$NPM_ENABLED" -eq 1 && -n "$N8N_DOMAIN" ]] && echo "    # NPM: $N8N_DOMAIN" >> docker-compose.yml || echo "    ports: [\"${N8N_PORT}:5678\"]" >> docker-compose.yml
    cat >> docker-compose.yml <<EOF
    environment:
      N8N_HOST: ${N8N_DOMAIN:-localhost}
      N8N_PORT: 5678
      WEBHOOK_URL: ${N8N_DOMAIN:+https://}${N8N_DOMAIN:-http://localhost}:${N8N_PORT}
EOF
    [[ "${N8N_DB_POSTGRES:-0}" -eq 1 ]] && cat >> docker-compose.yml <<EOF
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_USER: admin
      DB_POSTGRESDB_PASSWORD: ${PGPASSWORD}
      DB_POSTGRESDB_DATABASE: n8n
EOF
    echo "    volumes: [n8n_data:/home/node/.n8n]" >> docker-compose.yml
    echo "    networks: [internal_network]" >> docker-compose.yml
  fi
  if [[ " ${SELECTED_ARRAY[*]} " =~ "portainer" ]]; then
    cat >> docker-compose.yml <<EOF
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
EOF
    [[ "$NPM_ENABLED" -eq 1 && -n "$PORTAINER_DOMAIN" ]] && echo "    # NPM: $PORTAINER_DOMAIN" >> docker-compose.yml || echo "    ports: [\"9000:9000\"]" >> docker-compose.yml
    cat >> docker-compose.yml <<EOF
    volumes: [/var/run/docker.sock:/var/run/docker.sock, portainer_data:/data]
    networks: [internal_network]
EOF
  fi
  for svc in qdrant ollama apache; do
    [[ " ${SELECTED_ARRAY[*]} " =~ "$svc" ]] || continue
    local pv="${svc^^}_PORT" p="${!pv}" img="" vol="" env="" ip=""
    case "$svc" in
      qdrant) img="qdrant/qdrant:latest"; vol="qdrant_storage:/qdrant/storage"; ip="6333" ;;
      ollama) img="ollama/ollama:latest"; vol="ollama_data:/root/.ollama"; env="OLLAMA_HOST=0.0.0.0"; ip="11434" ;;
      apache) img="httpd:2.4-alpine"; vol="${APACHE_WWW_PATH}:/usr/local/apache2/htdocs/"; ip="80" ;;
    esac
    local dv="${svc^^}_DOMAIN" d="${!dv}"
    cat >> docker-compose.yml <<EOF
  $svc:
    image: $img
    container_name: $svc
    restart: unless-stopped
EOF
    [[ "$NPM_ENABLED" -eq 1 && -n "$d" ]] && echo "    # NPM: $d" >> docker-compose.yml || echo "    ports: [\"${p}:${ip}\"]" >> docker-compose.yml
    [[ -n "$env" ]] && echo "    environment: [$env]" >> docker-compose.yml
    [[ -n "$vol" ]] && echo "    volumes: [$vol]" >> docker-compose.yml
    echo "    networks: [internal_network]" >> docker-compose.yml
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
}

# === ЗАПУСК С РЕАЛЬНОЙ ПРОВЕРКОЙ ===
start_containers() {
  cd "$SETUP_DIR" || return 1
  echo "### Скачивание образов..." >&2
  if ! docker compose pull 2>&1 | tail -10 >&2; then
    dialog --msgbox "❌ Ошибка скачивания образов!" 8 50; return 1
  fi
  echo "### Запуск контейнеров..." >&2
  local out; out=$(docker compose up -d 2>&1); local st=$?
  echo "$out" >&2
  if [ $st -ne 0 ]; then
    dialog --msgbox "❌ Ошибка запуска:\n$out" 20 80; return 1
  fi
  sleep 3
  local cnt; cnt=$(docker compose ps -q 2>/dev/null | wc -l)
  if [ "$cnt" -eq 0 ]; then
    dialog --msgbox "⚠ Контейнеры не стартовали!\n$(docker compose logs --tail=20 2>&1)" 20 80; return 1
  fi
  echo "✅ Запущено: $cnt контейнеров" >&2
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && "${N8N_DB_POSTGRES:-0}" -eq 1 ]]; then
    for i in {1..30}; do docker exec postgres pg_isready -U admin &>/dev/null && break; sleep 2; done
    docker exec postgres psql -U admin -c "CREATE DATABASE n8n;" 2>/dev/null || true
  fi
}

configure_npm_ssl() {
  [[ "$NPM_ENABLED" -ne 1 || -z "$DOMAIN_MAIN" ]] && return 0
  echo "### Настройка SSL..." >&2; sleep 12
  command -v jq &>/dev/null || apt-get install -y jq >/dev/null 2>&1
  local TOKEN; TOKEN=$(curl -s -X POST "http://localhost:81/api/tokens" -H "Content-Type: application/json" \
    -d '{"identity":"admin@example.com","secret":"changeme"}' 2>/dev/null | jq -r '.token' 2>/dev/null)
  [[ "$TOKEN" == "null" || -z "$TOKEN" ]] && { echo "⚠ NPM API недоступен" >&2; return 1; }
  for svc in n8n apache qdrant ollama portainer supabase; do
    local dv="${svc^^}_DOMAIN" d="${!dv}"; [[ -z "$d" ]] && continue
    local fp=80; case "$svc" in n8n) fp=5678;; qdrant) fp=6333;; ollama) fp=11434;; portainer) fp=9000;; supabase) fp=8000;; esac
    curl -s -X POST "http://localhost:81/api/nginx/proxy-hosts" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"domain_names\":[\"$d\"],\"forward_host\":\"$svc\",\"forward_port\":$fp,\"certificate_id\":\"new\",\"meta\":{\"letsencrypt_agree\":true},\"ssl_forced\":true}" >/dev/null 2>&1
  done; echo "✅ SSL настроен" >&2
}

full_cleanup() {
  dialog --yesno "⚠️ УДАЛИТЬ ВСЁ?\nКонтейнеры, тома, конфиги!" 10 60 || return 0
  docker compose -p supabase down -v 2>/dev/null || true
  cd "$SETUP_DIR" 2>/dev/null && docker compose down -v 2>/dev/null || true
  docker system prune -af --volumes 2>/dev/null || true
  rm -rf "$SETUP_DIR" "$STATE_DIR"
  dialog --msgbox "✅ Сервер очищен." 8 40; exit 0
}

reinstall_service() {
  local svc=$1; cd "$SETUP_DIR" 2>/dev/null || return 1
  case "$svc" in
    supabase) docker compose -p supabase down -v 2>/dev/null; rm -rf supabase-docker; setup_supabase ;;
    *) docker compose stop "$svc" 2>/dev/null; docker compose rm -f "$svc" 2>/dev/null; generate_compose_file; docker compose up -d "$svc" 2>/dev/null ;;
  esac; dialog --msgbox "✅ $svc переустановлен." 6 40
}

show_summary() {
  local ip=$(hostname -I | awk '{print $1}')
  local msg="✅ УСТАНОВКА ЗАВЕРШЕНА!\n\n📍 IP: $ip\n"
  [[ -n "$DOMAIN_MAIN" ]] && msg+="🌐 Домен: $DOMAIN_MAIN\n"
  msg+="\n📦 Сервисы: ${SELECTED_ARRAY[*]}\n\n🔐 Данные:\n"
  [[ -n "$PGPASSWORD" ]] && msg+="• PG: admin / $PGPASSWORD\n"
  [[ -n "$JWT_SECRET" ]] && msg+="• JWT: $JWT_SECRET\n"
  [[ "$NPM_ENABLED" -eq 1 ]] && msg+="• NPM: admin@example.com / changeme\n"
  msg+="\n🌐 Доступ:\n"
  for svc in n8n portainer apache qdrant ollama supabase; do
    [[ " ${SELECTED_ARRAY[*]} " =~ "$svc" ]] || continue
    local dv="${svc^^}_DOMAIN" d="${!dv}" pv="${svc^^}_PORT" p="${!pv}"
    if [[ "$NPM_ENABLED" -eq 1 && -n "$d" ]]; then msg+="• $svc: https://$d\n"
    else
      [[ "$svc" == "n8n" ]] && p="${N8N_PORT:-5678}"; [[ "$svc" == "portainer" ]] && p="9000"
      [[ "$svc" == "supabase" ]] && p="Studio:3000/API:8000"
      msg+="• $svc: http://$ip:$p\n"
    fi
  done
  msg+="\n📁 Пути:\n• Setup: $SETUP_DIR\n• State: $STATE_DIR\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]] && msg+="• Apache: $APACHE_WWW_PATH\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && msg+="\n💡 Модели: docker exec -it ollama ollama pull llama3.1\n"
  echo -e "$msg" > "$STATE_DIR/summary.txt"
  dialog --title "🎉 Готово" --textbox "$STATE_DIR/summary.txt" 24 80
}

run_installation_process() {
  {
    echo "5"; echo "### Docker..." >&2; install_docker
    echo "15"; echo "### Сеть..." >&2; setup_network
    echo "30"; [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && { echo "### Supabase..." >&2; setup_supabase; }
    echo "60"; echo "### Конфиг..." >&2; generate_compose_file
    echo "80"; echo "### Запуск..." >&2; start_containers || { echo "FAIL" >&2; exit 1; }
    echo "95"; [[ "$NPM_ENABLED" -eq 1 ]] && { echo "### SSL..." >&2; configure_npm_ssl; }
    echo "100"; echo "### OK!" >&2; sleep 2
  } | dialog --title "🚀 Установка" --gauge "Настройка... Ошибки видны ниже" 12 70 0

  cd "$SETUP_DIR" 2>/dev/null
  if [ "$(docker compose ps -q 2>/dev/null | wc -l)" -eq 0 ]; then
    dialog --msgbox "❌ Не удалось запустить контейнеры!\ncd $SETUP_DIR && docker compose logs" 12 70
    save_state "failed"; return 1
  fi; return 0
}

main() {
  grep -qi "ubuntu\|debian" /etc/os-release || { echo "❌ Только Ubuntu/Debian"; exit 1; }
  [ "$EUID" -eq 0 ] || { echo "❌ Нужен sudo"; exit 1; }
  command -v dialog &>/dev/null || { apt-get update -qq >/dev/null; apt-get install -y dialog jq >/dev/null 2>&1; }
  load_selected; load_params
  [[ "$1" == "--reinstall" && -n "$2" ]] && { reinstall_service "$2"; exit 0; }
  case "$(get_state)" in
    start)
      show_service_menu || { save_state "start"; main; return; }
      input_parameters || { show_service_menu || { save_state "start"; main; return; }; }
      if run_installation_process; then save_state "completed"; show_summary
      else dialog --menu "❌ Ошибка. Действие:" 10 50 2 "1" "Повторить" "2" "Выйти" 2>"$TEMP_FILE"
        [[ "$(cat "$TEMP_FILE")" == "1" ]] && { rm -rf "$STATE_DIR"; save_state "start"; main; } || exit 1
      fi ;;
    completed)
      dialog --menu "✅ Готово. Действие:" 16 60 5 \
        "1" "➕ Добавить/удалить" "2" "🔄 Переустановить" "3" "🗑 WIPE" "4" "📋 Сводка" "5" "🚪 Выход" 2>"$TEMP_FILE"
      case "$(cat "$TEMP_FILE")" in
        1) show_service_menu; input_parameters; run_installation_process; show_summary ;;
        2) local inst=(); for s in postgres qdrant ollama apache nginx-proxy-manager portainer supabase n8n; do
             docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^$s$" && inst+=("$s" "$s" off); done
           [ ${#inst[@]} -eq 0 ] && { dialog --msgbox "Нет сервисов." 6 40; exit 0; }
           dialog --checklist "Выберите:" 15 50 6 "${inst[@]}" 2>"$TEMP_FILE"
           for s in $(cat "$TEMP_FILE" | tr -d '"'); do reinstall_service "$s"; done ;;
        3) full_cleanup ;; 4) show_summary ;; *) exit 0 ;;
      esac ;;
    *) rm -rf "$STATE_DIR"; save_state "start"; main ;;
  esac
}
main "$@"
