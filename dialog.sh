#!/bin/bash

# Проверка наличия утилиты dialog
if ! command -v dialog &> /dev/null; then
    echo "Ошибка: утилита 'dialog' не установлена."
    echo "Установите её командой: sudo apt install dialog"
    exit 1
fi

# Очистка экрана
clear

# ==========================================
# 1. Окно приветствия (РАЗМЕР 12x60)
# ==========================================
dialog --backtitle "Docker Installer" \
       --title "Добро пожаловать" \
       --yes-label "Начать" \
       --no-label "Выход" \
       --yesno "Добро пожаловать в установщик Docker контейнеров!\n\nНажмите 'Начать', чтобы продолжить." 12 60

if [ $? -ne 0 ]; then
    clear
    exit 0
fi

# ==========================================
# 2. Окно выбора сервисов (РАЗМЕР 15x70)
# ==========================================
choices=$(dialog --stdout \
                 --backtitle "Docker Installer" \
                 --title "Выбор сервисов" \
                 --ok-label "Установить" \
                 --cancel-label "Отмена" \
                 --checklist "Выберите сервисы:" 15 70 8 \
                 "PostgreSQL"   "База данных" OFF \
                 "Qdrant"       "Векторная БД" OFF \
                 "Ollama"       "LLM Ollama" OFF \
                 "Apache"       "Веб-сервер" OFF \
                 "NginxProxy"   "Nginx Proxy" OFF \
                 "Portainer"    "Portainer" OFF \
                 "Supabase"     "Supabase" OFF \
                 "n8n"          "n8n" OFF)

if [ $? -ne 0 ]; then
    dialog --title "Отмена" --msgbox "Установка отменена." 8 60
    clear
    exit 0
fi

if [ -z "$choices" ]; then
    dialog --title "Ошибка" --msgbox "Вы не выбрали ни одного сервиса!" 8 60
    clear
    exit 1
fi

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')

# ==========================================
# 3. Окно подтверждения (РАЗМЕР 12x60)
# ==========================================
dialog --title "Подтверждение" \
       --yes-label "Установить" \
       --no-label "Отмена" \
       --yesno "Будут установлены:\n\n1. Docker Engine\n2. Docker Compose\n3. Контейнеры:\n\n$(echo "$clean_choices" | sed 's/^/   - /')\n\nПродолжить?" 12 60

if [ $? -ne 0 ]; then
    clear
    exit 0
fi

# ==========================================
# 4. Имитация процесса установки
# ==========================================
dialog --title "Установка" \
       --infobox "\nУстановка Docker Engine...\nПожалуйста, подождите.\n" 8 60
sleep 2

dialog --title "Установка" \
       --infobox "\nDocker установлен!\n\nУстановка контейнеров:\n\n$(echo "$clean_choices" | sed 's/^/   - /')\n" 12 60
sleep 2

# ==========================================
# 5. Генерация данных доступа
# ==========================================
service_info=""

for service in $clean_choices; do
    case "$service" in
        PostgreSQL)
            password=$(openssl rand -base64 12)
            service_info="${service_info}\n\nPostgreSQL:"
            service_info="${service_info}\n  Порт: 5432"
            service_info="${service_info}\n  Пользователь: postgres"
            service_info="${service_info}\n  Пароль: ${password}"
            ;;
        Qdrant)
            service_info="${service_info}\n\nQdrant:"
            service_info="${service_info}\n  Порт: 6333"
            service_info="${service_info}\n  API: http://localhost:6333"
            ;;
        Ollama)
            service_info="${service_info}\n\nOllama:"
            service_info="${service_info}\n  Порт: 11434"
            service_info="${service_info}\n  API: http://localhost:11434"
            ;;
        Apache)
            service_info="${service_info}\n\nApache:"
            service_info="${service_info}\n  HTTP: 80"
            service_info="${service_info}\n  HTTPS: 443"
            ;;
        NginxProxy)
            admin_password=$(openssl rand -base64 12)
            service_info="${service_info}\n\nNginx Proxy Manager:"
            service_info="${service_info}\n  Панель: http://localhost:81"
            service_info="${service_info}\n  Email: admin@example.com"
            service_info="${service_info}\n  Пароль: ${admin_password}"
            ;;
        Portainer)
            service_info="${service_info}\n\nPortainer:"
            service_info="${service_info}\n  Порт: 9443"
            service_info="${service_info}\n  URL: https://localhost:9443"
            ;;
        Supabase)
            service_info="${service_info}\n\nSupabase:"
            service_info="${service_info}\n  Studio: http://localhost:8001"
            service_info="${service_info}\n  Postgres: localhost:54322"
            ;;
        n8n)
            service_info="${service_info}\n\nn8n:"
            service_info="${service_info}\n  Порт: 5678"
            service_info="${service_info}\n  URL: http://localhost:5678"
            ;;
    esac
done

# ==========================================
# 6. Финальное окно "Готово"
# ==========================================
dialog --title "Готово" --msgbox "\nУстановка успешно завершена!\n" 8 60

# ==========================================
# 7. Окно с информацией (РАЗМЕР 20x70)
# ==========================================
dialog --title "Информация" \
       --backtitle "Docker Installer" \
       --msgbox "Установленные сервисы:\n${service_info}\n\nВАЖНО: Сохраните эти данные!" 20 70

# Финальная очистка экрана
clear
echo "=========================================="
echo "Установка завершена!"
echo "=========================================="
echo ""
echo "Установленные сервисы:"
echo -e "$clean_choices" | sed 's/^/  ✓ /'
echo ""
echo "Данные доступа:${service_info}"
echo ""
echo "=========================================="
