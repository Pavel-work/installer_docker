#!/bin/bash
# Универсальный установщик сервисов v5.0 (WORKING VERSION)

# === Безопасная обработка pipe ===
if [ ! -t 0 ] && [ -z "$SCRIPT_SELF_EXECUTED" ]; then
  export SCRIPT_SELF_EXECUTED=1
  exec bash <(cat) "$@"
fi

# Цвета
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Переменные
STATE_DIR="/root/.server-setup-state"
STATE_FILE="$STATE_DIR/state.cfg"
SELECTED_FILE="$STATE_DIR/selected_services.cfg"
PARAMS_FILE="$STATE_DIR/params.env"
SETUP_DIR="/root/server-setup"
TEMP_FILE=$(mktemp)
REAL_USER="${SUDO_USER:-$USER}"

cleanup() { rm -f "$TEMP_FILE" 2>/dev/null; }
trap cleanup EXIT

save_state() { mkdir -p "$STATE_DIR"; echo "$1" > "$STATE_FILE"; }
get_state() { [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "start"; }

save_selected() {
  mkdir -p "$STATE_DIR"
  printf '%s\n' "${SELECTED_ARRAY[@]}" > "$SELECTED_FILE"
}

load_selected() {
  SELECTED_ARRAY=()
  [[ -f "$SELECTED_FILE" ]] && while IFS= read -r line; do
    [[ -n "$line" ]] && SELECTED_ARRAY+=("$line")
  done < "$SELECTED_FILE"
}

save_params() {
  mkdir -p "$STATE_DIR"
  cat > "$PARAMS_FILE" <<EOF
PGPASSWORD="${PGPASSWORD}"
JWT_SECRET="${JWT_SECRET}"
LLM_TYPE="${LLM_TYPE}"
LLM_API_KEY="${LLM_API_KEY}"
LLM_API_URL="${LLM_API_URL}"
DOMAIN_MAIN="${DOMAIN_MAIN}"
SUPABASE_DOMAIN="${SUPABASE_DOMAIN}"
N8N_PORT="${N8N_PORT}"
N8N_DOMAIN="${N8N_DOMAIN}"
N8N_DB_POSTGRES="${N8N_DB_POSTGRES}"
APACHE_WWW_PATH="${APACHE_WWW_PATH}"
APACHE_PORT="${APACHE_PORT}"
QDRANT_PORT="${QDRANT_PORT}"
OLLAMA_PORT="${OLLAMA_PORT}"
NPM_ENABLED="${NPM_ENABLED}"
EOF
  chmod 600 "$PARAMS_FILE"
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
  QDRANT_PORT="${QDRANT_PORT:-6333}"
  OLLAMA_PORT="${OLLAMA_PORT:-11434}"
  NPM_ENABLED="${NPM_ENABLED:-0}"
}

read_input() {
  local prompt="$1" default="$2" var_name="$3"
  dialog --clear --title "Ввод" --inputbox "$prompt" 12 70 "$default" 2>"$TEMP_FILE"
  [[ $? -ne 0 ]] && return 1
  eval "$var_name=\"\$(cat "$TEMP_FILE")\""
  return 0
}

check_port() {
  local port=$1
  if command -v ss &>/dev/null && ss -Htuln sport = :$port 2>/dev/null | grep -q .; then
    dialog --msgbox "Порт $port занят!" 6 40
    return 1
  fi
  return 0
}

install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "### Установка Docker..." >&2
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "$REAL_USER" 2>/dev/null || true
    systemctl enable docker --now >/dev/null 2>&1 || true
  fi
  if ! docker compose version &>/dev/null; then
    apt-get update -qq && apt-get install -y docker-compose-plugin
  fi
}

show_menu() {
  dialog --clear --title "Выберите сервисы" \
    --checklist "Пробел=выбор, Enter=далее" 18 60 8 \
    "postgres" "PostgreSQL" $([[ " ${SELECTED_ARRAY[*]} " =~ "postgres" ]] && echo "on" || echo "off") \
    "n8n" "n8n" $([[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]] && echo "on" || echo "off") \
    "portainer" "Portainer" $([[ " ${SELECTED_ARRAY[*]} " =~ "portainer" ]] && echo "on" || echo "off") \
    "nginx_proxy" "Nginx Proxy Manager" $([[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]] && echo "on" || echo "off") \
    "supabase" "Supabase" $([[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]] && echo "on" || echo "off") \
    "ollama" "Ollama" $([[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && echo "on" || echo "off") \
    "qdrant" "Qdrant" $([[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]] && echo "on" || echo "off") \
    "apache" "Apache" $([[ " ${SELECTED_ARRAY[*]} " =~ "apache" ]] && echo "on" || echo "off") \
    2>"$TEMP_FILE"
  [[ $? -ne 0 ]] && return 1
  
  SELECTED_ARRAY=()
  for item in $(cat "$TEMP_FILE" | tr -d '"'); do
    SELECTED_ARRAY+=("$item")
  done
  
  [[ ${#SELECTED_ARRAY[@]} -eq 0 ]] && { dialog --msgbox "Выберите хотя бы один!" 6 50; return 1; }
  save_selected
}

input_params() {
  # PostgreSQL
  if [[ " ${SELECTED_ARRAY[*]} " =~ "postgres" || " ${SELECTED_ARRAY[*]} " =~ "supabase" || " ${SELECTED_ARRAY[*]} " =~ "n8n" ]]; then
    read_input "Пароль PostgreSQL (admin):" "$PGPASSWORD" "PGPASSWORD" || return 1
    [[ -z "$PGPASSWORD" ]] && PGPASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c16)
  fi
  
  # JWT для Supabase
  if [[ " ${SELECTED_ARRAY[*]} " =~ "supabase" ]]; then
    read_input "JWT Secret (пусто=авто):" "$JWT_SECRET" "JWT_SECRET" || return 1
    [[ -z "$JWT_SECRET" ]] && JWT_SECRET=$(openssl rand -hex 32)
  fi
  
  # NPM
  if [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]]; then
    NPM_ENABLED=1
    read_input "Основной домен:" "$DOMAIN_MAIN" "DOMAIN_MAIN" || return 1
  fi
  
  # Порты
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]]; then
    read_input "Порт n8n:" "${N8N_PORT:-5678}" "N8N_PORT" || return 1
    check_port "$N8N_PORT" || return 1
  fi
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]]; then
    read_input "Порт Qdrant:" "${QDRANT_PORT:-6333}" "QDRANT_PORT" || return 1
    check_port "$QDRANT_PORT" || return 1
  fi
  
  if [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]]; then
    read_input "Порт Ollama:" "${OLLAMA_PORT:-11434}" "OLLAMA_PORT" || return 1
    check_port "$OLLAMA_PORT" || return 1
  fi
  
  # n8n + Postgres
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && " ${SELECTED_ARRAY[*]} " =~ "postgres" ]]; then
    dialog --yesno "Использовать PostgreSQL для n8n?" 8 50
    [[ $? -eq 0 ]] && N8N_DB_POSTGRES=1 || N8N_DB_POSTGRES=0
  fi
  
  save_params
}

setup_network() {
  docker network inspect internal_network &>/dev/null || docker network create internal_network
  mkdir -p "$SETUP_DIR" && cd "$SETUP_DIR"
  
  cat > .env <<EOF
POSTGRES_PASSWORD=${PGPASSWORD}
JWT_SECRET=${JWT_SECRET}
EOF
  chmod 600 .env
}

generate_compose() {
  cd "$SETUP_DIR"
  
  cat > docker-compose.yml <<'EOF'
networks:
  internal_network:
    external: true
volumes:
EOF
  
  [[ " ${SELECTED_ARRAY[*]} " =~ "postgres" ]] && echo "  postgres_data:" >> docker-compose.yml
  [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]] && echo "  n8n_data:" >> docker-compose.yml
  [[ " ${SELECTED_ARRAY[*]} " =~ "portainer" ]] && echo "  portainer_data:" >> docker-compose.yml
  [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]] && { echo "  npm_data:"; echo "  npm_ssl:"; } >> docker-compose.yml
  [[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]] && echo "  qdrant_data:" >> docker-compose.yml
  [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && echo "  ollama_data:" >> docker-compose.yml
  
  echo "services:" >> docker-compose.yml
  
  # PostgreSQL
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
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - internal_network
EOF
  fi
  
  # n8n
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]]; then
    cat >> docker-compose.yml <<EOF
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    environment:
      - N8N_HOST=localhost
      - N8N_PORT=5678
      - WEBHOOK_URL=http://localhost:${N8N_PORT}
EOF
    if [[ "${N8N_DB_POSTGRES:-0}" -eq 1 ]]; then
      cat >> docker-compose.yml <<EOF
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=admin
      - DB_POSTGRESDB_PASSWORD=${PGPASSWORD}
      - DB_POSTGRESDB_DATABASE=n8n
EOF
    fi
    cat >> docker-compose.yml <<EOF
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - internal_network
EOF
  fi
  
  # Portainer
  if [[ " ${SELECTED_ARRAY[*]} " =~ "portainer" ]]; then
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
  
  # Nginx Proxy Manager
  if [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]]; then
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
      - npm_ssl:/etc/letsencrypt
    networks:
      - internal_network
EOF
  fi
  
  # Qdrant
  if [[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]]; then
    cat >> docker-compose.yml <<EOF
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    ports:
      - "${QDRANT_PORT}:6333"
    volumes:
      - qdrant_data:/qdrant/storage
    networks:
      - internal_network
EOF
  fi
  
  # Ollama
  if [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]]; then
    cat >> docker-compose.yml <<EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "${OLLAMA_PORT}:11434"
    volumes:
      - ollama_data:/root/.ollama
    networks:
      - internal_network
EOF
  fi
}

start_services() {
  cd "$SETUP_DIR"
  
  echo "### Скачивание образов..." >&2
  if ! docker compose pull; then
    dialog --msgbox "❌ Ошибка скачивания образов!" 8 50
    return 1
  fi
  
  echo "### Запуск контейнеров..." >&2
  if ! docker compose up -d; then
    dialog --msgbox "❌ Ошибка запуска:\n\n$(docker compose logs 2>&1 | tail -30)" 20 80
    return 1
  fi
  
  sleep 3
  
  local count=$(docker compose ps -q 2>/dev/null | wc -l)
  if [[ "$count" -eq 0 ]]; then
    dialog --msgbox "⚠ Контейнеры не запустились!\n\n$(docker compose logs --tail=30)" 20 80
    return 1
  fi
  
  # Создание БД для n8n
  if [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" && "${N8N_DB_POSTGRES:-0}" -eq 1 ]]; then
    echo "### Создание БД n8n..." >&2
    for i in {1..30}; do
      if docker exec postgres pg_isready -U admin &>/dev/null; then
        docker exec postgres psql -U admin -c "CREATE DATABASE n8n;" 2>/dev/null || true
        break
      fi
      sleep 2
    done
  fi
  
  echo "✅ Запущено контейнеров: $count" >&2
}

show_result() {
  local ip=$(hostname -I | awk '{print $1}')
  local msg="✅ ГОТОВО!\n\n📍 IP: $ip\n\n📦 Сервисы:\n"
  
  for s in "${SELECTED_ARRAY[@]}"; do msg+="  • $s\n"; done
  
  msg+="\n🔐 Данные:\n"
  [[ -n "$PGPASSWORD" ]] && msg+="  PostgreSQL: admin / $PGPASSWORD\n"
  [[ -n "$JWT_SECRET" ]] && msg+="  JWT: $JWT_SECRET\n"
  [[ "$NPM_ENABLED" -eq 1 ]] && msg+="  NPM: admin@example.com / changeme\n"
  
  msg+="\n🌐 Доступ:\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "n8n" ]] && msg+="  n8n: http://$ip:${N8N_PORT}\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "portainer" ]] && msg+="  Portainer: http://$ip:9000\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "nginx_proxy" ]] && msg+="  NPM: http://$ip:81\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "qdrant" ]] && msg+="  Qdrant: http://$ip:${QDRANT_PORT}\n"
  [[ " ${SELECTED_ARRAY[*]} " =~ "ollama" ]] && msg+="  Ollama: http://$ip:${OLLAMA_PORT}\n"
  
  msg+="\n📁 Папки:\n  $SETUP_DIR\n  $STATE_DIR\n"
  
  echo -e "$msg" > "$STATE_DIR/result.txt"
  dialog --title "Установка завершена" --textbox "$STATE_DIR/result.txt" 22 70
}

run_install() {
  {
    echo "10"; echo "### Docker..." >&2; install_docker
    echo "30"; echo "### Сеть..." >&2; setup_network
    echo "50"; echo "### Конфиг..." >&2; generate_compose
    echo "70"; echo "### Запуск..." >&2; start_services || { echo "FAIL"; exit 1; }
    echo "100"; echo "### OK" >&2
  } | dialog --gauge "Установка..." 10 60 0
  
  [[ "$(docker compose ps -q 2>/dev/null | wc -l)" -eq 0 ]] && return 1
  return 0
}

main() {
  [[ "$EUID" -ne 0 ]] && { echo "Нужен sudo/root"; exit 1; }
  grep -qi "ubuntu\|debian" /etc/os-release || { echo "Только Ubuntu/Debian"; exit 1; }
  
  command -v dialog &>/dev/null || { apt-get update -qq && apt-get install -y dialog jq; }
  
  load_selected; load_params
  
  case "$(get_state)" in
    start)
      show_menu || exit 1
      input_params || exit 1
      if run_install; then
        save_state "completed"
        show_result
      else
        dialog --msgbox "❌ Ошибка установки" 8 50
        exit 1
      fi
      ;;
    completed)
      dialog --menu "Действие:" 12 50 3 \
        "1" "Переустановить" "2" "WIPE" "3" "Выход" 2>"$TEMP_FILE"
      case "$(cat "$TEMP_FILE")" in
        1) rm -rf "$STATE_DIR"; save_state "start"; main ;;
        2) docker compose -C "$SETUP_DIR" down -v 2>/dev/null; rm -rf "$SETUP_DIR" "$STATE_DIR"; dialog --msgbox "Удалено"; exit 0 ;;
      esac
      ;;
  esac
}

main "$@"
