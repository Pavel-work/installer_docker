#!/bin/bash

# Проверка наличия утилиты dialog
if ! command -v dialog &> /dev/null; then
    echo "Ошибка: утилита 'dialog' не установлена."
    echo "Установите: sudo apt install dialog"
    exit 1
fi

clear

# ==========================================
# 1. Приветствие (10x60) - было 8x50
# ==========================================
dialog --backtitle "Docker Installer" \
       --title "Добро пожаловать" \
       --yes-label "Начать" --no-label "Выход" \
       --yesno "Добро пожаловать в установщик Docker!\n\nНажмите 'Начать' для продолжения." 10 60

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 2. Выбор сервисов (17x72) - было 14x60
# ==========================================
choices=$(dialog --stdout \
                 --backtitle "Docker Installer" \
                 --title "Выбор сервисов" \
                 --ok-label "Установить" --cancel-label "Отмена" \
                 --checklist "Отметьте нужные сервисы (пробел - выбор):" 17 72 8 \
                 "PostgreSQL" "База данных PostgreSQL" OFF \
                 "Qdrant" "Векторная база Qdrant" OFF \
                 "Ollama" "Локальная LLM Ollama" OFF \
                 "Apache" "Веб-сервер Apache" OFF \
                 "NginxProxy" "Nginx Proxy Manager" OFF \
                 "Portainer" "Управление Docker" OFF \
                 "Supabase" "Supabase Full Stack" OFF \
                 "n8n" "Автоматизация n8n" OFF)

[ $? -ne 0 ] && { dialog --msgbox "Установка отменена." 8 60; clear; exit 0; }
[ -z "$choices" ] && { dialog --msgbox "Выберите хотя бы один сервис!" 8 60; clear; exit 1; }

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')

# ==========================================
# 3. Подтверждение (12x60) - было 10x50
# ==========================================
dialog --title "Подтверждение" \
       --yes-label "Установить" --no-label "Отмена" \
       --yesno "Будут установлены:\n\n1. Docker Engine\n2. Docker Compose\n3. Сервисы:\n$(echo "$clean_choices" | sed 's/^/   - /')\n\nПродолжить?" 12 60

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 4. Установка (имитация) (8x60) - было 6x50
# ==========================================
dialog --infobox "\nУстановка Docker Engine...\nПожалуйста, подождите.\n" 8 60
sleep 1

dialog --infobox "\nDocker установлен!\n\nУстановка выбранных сервисов...\n" 8 60
sleep 1

# ==========================================
# 5. Генерация данных
# ==========================================
service_info=""
for service in $clean_choices; do
    case "$service" in
        PostgreSQL)
            pass=$(openssl rand -base64 10)
            service_info="${service_info}\n\nPostgreSQL:"
            service_info="${service_info}\n  Порт: 5432"
            service_info="${service_info}\n  Пользователь: postgres"
            service_info="${service_info}\n  Пароль: $pass" ;;
        Qdrant)
            service_info="${service_info}\n\nQdrant:"
            service_info="${service_info}\n  Порт REST: 6333"
            service_info="${service_info}\n  Порт gRPC: 6334"
            service_info="${service_info}\n  URL: http://localhost:6333" ;;
        Ollama)
            service_info="${service_info}\n\nOllama:"
            service_info="${service_info}\n  Порт: 11434"
            service_info="${service_info}\n  API: http://localhost:11434" ;;
        Apache)
            service_info="${service_info}\n\nApache:"
            service_info="${service_info}\n  HTTP: 80"
            service_info="${service_info}\n  HTTPS: 443"
            service_info="${service_info}\n  URL: http://localhost" ;;
        NginxProxy)
            pass=$(openssl rand -base64 10)
            service_info="${service_info}\n\nNginx Proxy Manager:"
            service_info="${service_info}\n  HTTP: 80, HTTPS: 443"
            service_info="${service_info}\n  Панель: http://localhost:81"
            service_info="${service_info}\n  Email: admin@example.com"
            service_info="${service_info}\n  Пароль: $pass" ;;
        Portainer)
            service_info="${service_info}\n\nPortainer:"
            service_info="${service_info}\n  HTTP: 9000"
            service_info="${service_info}\n  HTTPS: 9443"
            service_info="${service_info}\n  URL: https://localhost:9443" ;;
        Supabase)
            service_info="${service_info}\n\nSupabase (Full):"
            service_info="${service_info}\n  Kong API: http://localhost:8000"
            service_info="${service_info}\n  Studio: http://localhost:8001"
            service_info="${service_info}\n  Postgres: localhost:54322" ;;
        n8n)
            service_info="${service_info}\n\nn8n:"
            service_info="${service_info}\n  Порт: 5678"
            service_info="${service_info}\n  URL: http://localhost:5678" ;;
    esac
done

# ==========================================
# 6. Готово + Информация (18x72) - было 15x60
# ==========================================
dialog --title "Установка завершена" \
       --backtitle "Docker Installer" \
       --msgbox "✓ Установка успешно завершена!\n\n========================================\nДАННЫЕ ДОСТУПА:\n========================================${service_info}\n\n========================================\nВАЖНО: Сохраните эти данные!\n========================================" 18 72

clear
echo "=========================================="
echo "✓ Установка завершена!"
echo "=========================================="
echo ""
echo "Установленные сервисы:"
echo -e "$clean_choices" | sed 's/^/  ✓ /'
echo ""
echo "Данные доступа:${service_info}"
echo ""
echo "=========================================="
