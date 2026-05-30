#!/bin/bash

# Проверка наличия утилиты dialog
if ! command -v dialog &> /dev/null; then
    echo "Ошибка: утилита 'dialog' не установлена."
    echo "Установите: sudo apt install dialog"
    exit 1
fi

clear

# ==========================================
# 1. Приветствие (12x72) - было 10x60
# ==========================================
dialog --backtitle "Docker Installer" \
       --title "Добро пожаловать" \
       --yes-label "Начать" --no-label "Выход" \
       --yesno "Добро пожаловать в установщик Docker контейнеров!\n\nНажмите 'Начать' для продолжения установки." 12 72

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 2. Выбор сервисов (20x86) - было 17x72
# ==========================================
choices=$(dialog --stdout \
                 --backtitle "Docker Installer" \
                 --title "Выбор сервисов" \
                 --ok-label "Установить" --cancel-label "Отмена" \
                 --checklist "Отметьте нужные сервисы для установки (пробел - выбор):" 20 86 10 \
                 "PostgreSQL" "База данных PostgreSQL" OFF \
                 "Qdrant" "Векторная база данных Qdrant" OFF \
                 "Ollama" "Локальная LLM Ollama" OFF \
                 "Apache" "Веб-сервер Apache HTTP" OFF \
                 "NginxProxy" "Nginx Proxy Manager" OFF \
                 "Portainer" "Управление Docker Portainer" OFF \
                 "Supabase" "Supabase Full Stack" OFF \
                 "n8n" "Автоматизация workflow n8n" OFF)

[ $? -ne 0 ] && { dialog --msgbox "Установка отменена пользователем." 10 72; clear; exit 0; }
[ -z "$choices" ] && { dialog --msgbox "Ошибка: Выберите хотя бы один сервис для установки!" 10 72; clear; exit 1; }

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')

# ==========================================
# 3. Подтверждение (14x72) - было 12x60
# ==========================================
dialog --title "Подтверждение установки" \
       --yes-label "Установить" --no-label "Отмена" \
       --yesno "Будут выполнены следующие действия:\n\n1. Установка Docker Engine\n2. Установка Docker Compose\n3. Установка выбранных сервисов:\n\n$(echo "$clean_choices" | sed 's/^/   • /')\n\nПродолжить установку?" 14 72

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 4. Установка (имитация) (10x72) - было 8x60
# ==========================================
dialog --infobox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n      УСТАНОВКА DOCKER ENGINE\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nЗагрузка и установка Docker...\nПожалуйста, подождите.\n" 10 72
sleep 2

dialog --infobox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n      УСТАНОВКА СЕРВИСОВ\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nDocker успешно установлен!\n\nУстановка выбранных сервисов:\n$(echo "$clean_choices" | sed 's/^/   • /')\n" 12 72
sleep 2

# ==========================================
# 5. Генерация данных
# ==========================================
service_info=""
for service in $clean_choices; do
    case "$service" in
        PostgreSQL)
            pass=$(openssl rand -base64 12)
            service_info="${service_info}\n\n📦 PostgreSQL:"
            service_info="${service_info}\n   Порт: 5432"
            service_info="${service_info}\n   Пользователь: postgres"
            service_info="${service_info}\n   Пароль: $pass"
            service_info="${service_info}\n   Подключение: psql -h localhost -U postgres" ;;
        Qdrant)
            service_info="${service_info}\n\n📦 Qdrant:"
            service_info="${service_info}\n   Порт REST: 6333"
            service_info="${service_info}\n   Порт gRPC: 6334"
            service_info="${service_info}\n   Web UI: http://localhost:6333/dashboard" ;;
        Ollama)
            service_info="${service_info}\n\n📦 Ollama:"
            service_info="${service_info}\n   Порт: 11434"
            service_info="${service_info}\n   API: http://localhost:11434"
            service_info="${service_info}\n   Пример: ollama pull llama2" ;;
        Apache)
            service_info="${service_info}\n\n📦 Apache:"
            service_info="${service_info}\n   HTTP Порт: 80"
            service_info="${service_info}\n   HTTPS Порт: 443"
            service_info="${service_info}\n   URL: http://localhost" ;;
        NginxProxy)
            pass=$(openssl rand -base64 12)
            service_info="${service_info}\n\n📦 Nginx Proxy Manager:"
            service_info="${service_info}\n   HTTP Порт: 80"
            service_info="${service_info}\n   HTTPS Порт: 443"
            service_info="${service_info}\n   Admin Panel: http://localhost:81"
            service_info="${service_info}\n   Email: admin@example.com"
            service_info="${service_info}\n   Пароль: $pass" ;;
        Portainer)
            service_info="${service_info}\n\n📦 Portainer:"
            service_info="${service_info}\n   HTTP Порт: 9000"
            service_info="${service_info}\n   HTTPS Порт: 9443"
            service_info="${service_info}\n   URL: https://localhost:9443"
            service_info="${service_info}\n   Создайте admin при первом входе" ;;
        Supabase)
            service_info="${service_info}\n\n📦 Supabase (Full):"
            service_info="${service_info}\n   Kong API: http://localhost:8000"
            service_info="${service_info}\n   Studio: http://localhost:8001"
            service_info="${service_info}\n   Auth: http://localhost:9999"
            service_info="${service_info}\n   Postgres: localhost:54322" ;;
        n8n)
            service_info="${service_info}\n\n📦 n8n:"
            service_info="${service_info}\n   Порт: 5678"
            service_info="${service_info}\n   URL: http://localhost:5678"
            service_info="${service_info}\n   Создайте пользователя при первом входе" ;;
    esac
done

# ==========================================
# 6. Готово + Информация (22x86) - было 18x72
# ==========================================
dialog --title "✓ Установка завершена успешно" \
       --backtitle "Docker Installer - Данные доступа" \
       --msgbox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n         УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nУстановленные сервисы:${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n         ⚠️  ВАЖНО: Сохраните эти данные!  ⚠️\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" 22 86

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "         ✓ УСТАНОВКА ЗАВЕРШЕНА!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Установленные сервисы:"
echo -e "$clean_choices" | sed 's/^/  ✓ /'
echo ""
echo "Данные доступа:${service_info}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
