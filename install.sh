#!/bin/bash
# Простой установщик контейнеров v1.1
# Архитектура: Меню → Параметры → Сеть → docker run → Итог
# Запуск: sudo bash install.sh

# Проверка прав и зависимостей
[ "$EUID" -ne 0 ] && { echo "❌ Нужен sudo/root"; exit 1; }
command -v dialog &>/dev/null || { apt-get update -qq && apt-get install -y dialog jq; }

# Установка Docker если нет
if ! command -v docker &>/dev/null; then
  echo "️  Установка Docker..."
  curl -fsSL https://get.docker.com | sh
  usermod -aG docker "$SUDO_USER" 2>/dev/null || true
fi

TEMP=$(mktemp)
trap "rm -f $TEMP" EXIT

# === 1. Меню выбора ===
dialog --clear --title "📦 Выберите контейнеры" \
  --checklist "Пробел = выбрать, Enter = далее" 15 60 7 \
  "postgres" "PostgreSQL" off \
  "n8n" "n8n (автоматизация)" off \
  "portainer" "Portainer (UI Docker)" off \
  "nginx" "Nginx Proxy Manager" off \
  "qdrant" "Qdrant (векторная БД)" off \
  "ollama" "Ollama (локальные LLM)" off \
  "apache" "Apache (веб-сервер)" off \
  2>"$TEMP"

[[ $? -ne 0 ]] && exit 1

SELECTED=($(cat "$TEMP" | tr -d '"'))
[[ ${#SELECTED[@]} -eq 0 ]] && { dialog --msgbox "⚠ Выберите хотя бы один!"; exit 1; }

# === 2. Сбор параметров ===
PG_PASS="changeme"
N8N_PORT=5678
APACHE_PORT=8080

# Запрос пароля PostgreSQL
if [[ " ${SELECTED[*]} " =~ "postgres" ]]; then
  dialog --clear --title "🔐 PostgreSQL" --passwordbox "Введите пароль для admin:" 10 60 "" 2>"$TEMP"
  [[ $? -ne 0 ]] && exit 1
  PG_PASS=$(cat "$TEMP")
  [[ -z "$PG_PASS" ]] && PG_PASS="changeme"
fi

# Запрос порта n8n
if [[ " ${SELECTED[*]} " =~ "n8n" ]]; then
  dialog --clear --title "🔌 n8n" --inputbox "Порт для n8n:" 10 60 "5678" 2>"$TEMP"
  [[ $? -ne 0 ]] && exit 1
  N8N_PORT=$(cat "$TEMP")
  [[ -z "$N8N_PORT" ]] && N8N_PORT=5678
fi

# Запрос порта Apache
if [[ " ${SELECTED[*]} " =~ "apache" ]]; then
  dialog --clear --title "🔌 Apache" --inputbox "Порт для Apache:" 10 60 "8080" 2>"$TEMP"
  [[ $? -ne 0 ]] && exit 1
  APACHE_PORT=$(cat "$TEMP")
  [[ -z "$APACHE_PORT" ]] && APACHE_PORT=8080
fi

# === 3. Создание общей сети ===
echo " Создание сети app-net..."
docker network create app-net 2>/dev/null || true

# === 4. Запуск контейнеров ===
cd /root
for svc in "${SELECTED[@]}"; do
  echo "🚀 Запуск $svc..."
  case "$svc" in
    postgres)
      docker run -d --name postgres --network app-net \
        -e POSTGRES_PASSWORD="$PG_PASS" \
        -e POSTGRES_USER=admin \
        -e POSTGRES_DB=appdb \
        -v postgres_data:/var/lib/postgresql/data \
        -p 5432:5432 \
        --restart unless-stopped \
        postgres:16-alpine
      ;;
    n8n)
      docker run -d --name n8n --network app-net \
        -v n8n_data:/home/node/.n8n \
        -p "${N8N_PORT}:5678" \
        --restart unless-stopped \
        n8nio/n8n:latest
      ;;
    portainer)
      docker run -d --name portainer --network app-net \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        -p 9000:9000 \
        --restart unless-stopped \
        portainer/portainer-ce:latest
      ;;
    nginx)
      docker run -d --name nginx-proxy-manager --network app-net \
        -v npm_data:/data \
        -v npm_ssl:/etc/letsencrypt \
        -p 80:80 -p 443:443 -p 81:81 \
        --restart unless-stopped \
        jc21/nginx-proxy-manager:latest
      ;;
    qdrant)
      docker run -d --name qdrant --network app-net \
        -v qdrant_data:/qdrant/storage \
        -p 6333:6333 \
        --restart unless-stopped \
        qdrant/qdrant:latest
      ;;
    ollama)
      docker run -d --name ollama --network app-net \
        -v ollama_data:/root/.ollama \
        -p 11434:11434 \
        --restart unless-stopped \
        ollama/ollama:latest
      ;;
    apache)
      docker run -d --name apache --network app-net \
        -v /root/www:/usr/local/apache2/htdocs \
        -p "${APACHE_PORT}:80" \
        --restart unless-stopped \
        httpd:2.4-alpine
      ;;
  esac
done

# === 5. Итоговое окно ===
IP=$(hostname -I | awk '{print $1}')
MSG="✅ ГОТОВО! IP: $IP\n\n Доступ к сервисам:\n"
[[ " ${SELECTED[*]} " =~ "n8n" ]] && MSG+="  • n8n: http://$IP:$N8N_PORT\n"
[[ " ${SELECTED[*]} " =~ "portainer" ]] && MSG+="  • Portainer: http://$IP:9000\n"
[[ " ${SELECTED[*]} " =~ "nginx" ]] && MSG+="  • NPM: http://$IP:81\n"
[[ " ${SELECTED[*]} " =~ "qdrant" ]] && MSG+="  • Qdrant: http://$IP:6333\n"
[[ " ${SELECTED[*]} " =~ "ollama" ]] && MSG+="  • Ollama: http://$IP:11434\n"
[[ " ${SELECTED[*]} " =~ "apache" ]] && MSG+="  • Apache: http://$IP:$APACHE_PORT\n"
[[ " ${SELECTED[*]} " =~ "postgres" ]] && MSG+="  • Postgres: localhost:5432 (admin/$PG_PASS)\n"

MSG+="\n🌐 Сеть: app-net (все контейнеры видят друг друга по именам)"
MSG+="\n📁 Данные: /var/lib/docker/volumes/"

dialog --clear --title " Установка завершена" --msgbox "$MSG" 22 70
