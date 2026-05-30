#!/bin/bash

# Проверка наличия утилиты dialog
if ! command -v dialog &> /dev/null; then
    echo "Ошибка: утилита 'dialog' не установлена."
    echo "Установите её командой: sudo apt install dialog (Debian/Ubuntu) или sudo yum install dialog (CentOS/RHEL)"
    exit 1
fi

# Очистка экрана при запуске
clear

# ==========================================
# 1. Окно приветствия (увеличенное)
# ==========================================
dialog --backtitle "Docker Installer" \
       --title "Добро пожаловать" \
       --yes-label "Начать" \
       --no-label "Выход" \
       --cr-wrap \
       --yesno "Добро пожаловать в установщик Docker контейнеров!\n\nНажмите 'Начать', чтобы продолжить." 15 100

if [ $? -ne 0 ]; then
    clear
    exit 0
fi

# ==========================================
# 2. Окно выбора сервисов (Checklist) - УВЕЛИЧЕНО
# ==========================================
choices=$(dialog --stdout \
                 --backtitle "Docker Installer" \
                 --title "Выбор сервисов" \
                 --ok-label "Установить" \
                 --cancel-label "Отмена" \
                 --checklist "Выберите какие сервисы хотите установить (пробел - выбор):" 28 120 10 \
                 "PostgreSQL"   "База данных PostgreSQL" OFF \
                 "Qdrant"       "Векторная база Qdrant" OFF \
                 "Ollama"       "Локальная LLM Ollama" OFF \
                 "Apache"       "Веб-сервер Apache" OFF \
                 "NginxProxy"   "Nginx Proxy Manager" OFF \
                 "Portainer"    "Управление Docker Portainer" OFF \
                 "Supabase"     "Supabase Full Stack" OFF \
                 "n8n"          "Workflow автоматизация n8n" OFF)

if [ $? -ne 0 ]; then
    dialog --title "Отмена" --msgbox "Установка отменена." 12 100
    clear
    exit 0
fi

if [ -z "$choices" ]; then
    dialog --title "Ошибка" --msgbox "Вы не выбрали ни одного сервиса!\nУстановка прервана." 12 100
    clear
    exit 1
fi

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')

# ==========================================
# 3. Окно подтверждения - УВЕЛИЧЕНО
# ==========================================
dialog --title "Подтверждение" \
       --yes-label "Установить" \
       --no-label "Отмена" \
       --cr-wrap \
       --yesno "Будут выполнены следующие действия:\n\n1. Установка Docker Engine\n2. Установка Docker Compose\n3. Установка выбранных контейнеров:\n\n$(echo "$clean_choices" | sed 's/^/   - /')\n\nПродолжить?" 25 100

if [ $? -ne 0 ]; then
    clear
    exit 0
fi

# ==========================================
# 4. Имитация процесса установки
# ==========================================
dialog --title "Установка" \
       --infobox "\nУстановка Docker Engine...\nПожалуйста, подождите.\n" 12 100
sleep 2

dialog --title "Установка" \
       --infobox "\nDocker установлен!\n\nУстанавливаем выбранные контейнеры:\n\n$(echo "$clean_choices" | sed 's/^/   - /')\n" 20 100
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
            service_info="${service_info}\n  Подключение: psql -h localhost -U postgres"
            ;;
        Qdrant)
            service_info="${service_info}\n\nQdrant:"
            service_info="${service_info}\n  Порт REST: 6333"
            service_info="${service_info}\n  Порт gRPC: 6334"
            service_info="${service_info}\n  Web UI: http://localhost:6333/dashboard"
            ;;
        Ollama)
            service_info="${service_info}\n\nOllama:"
            service_info="${service_info}\n  Порт: 11434"
            service_info="${service_info}\n  API: http://localhost:11434"
            service_info="${service_info}\n  Команда: ollama pull llama2"
            ;;
        Apache)
            service_info="${service_info}\n\nApache:"
            service_info="${service_info}\n  HTTP Порт: 80"
            service_info="${service_info}\n  HTTPS Порт: 443"
            service_info="${service_info}\n  URL: http://localhost"
            ;;
        NginxProxy)
            admin_password=$(openssl rand -base64 12)
            service_info="${service_info}\n\nNginx Proxy Manager:"
            service_info="${service_info}\n  HTTP Порт: 80"
            service_info="${service_info}\n  HTTPS Порт: 443"
            service_info="${service_info}\n  Admin Panel: http://localhost:81"
            service_info="${service_info}\n  Email: admin@example.com"
            service_info="${service_info}\n  Пароль: ${admin_password}"
            ;;
        Portainer)
            service_info="${service_info}\n\nPortainer:"
            service_info="${service_info}\n  HTTP Порт: 9000"
            service_info="${service_info}\n  HTTPS Порт: 9443"
            service_info="${service_info}\n  URL: https://localhost:9443"
            service_info="${service_info}\n  Создайте admin при первом входе"
            ;;
        Supabase)
            service_info="${service_info}\n\nSupabase (Full):"
            service_info="${service_info}\n  Kong API: http://localhost:8000"
            service_info="${service_info}\n  Studio: http://localhost:8001"
            service_info="${service_info}\n  Auth: http://localhost:9999"
            service_info="${service_info}\n  Postgres: localhost:54322"
            ;;
        n8n)
            service_info="${service_info}\n\nn8n:"
            service_info="${service_info}\n  Порт: 5678"
            service_info="${service_info}\n  URL: http://localhost:5678"
            service_info="${service_info}\n  Создайте пользователя при первом входе"
            ;;
    esac
done

# ==========================================
# 6. Финальное окно "Готово"
# ==========================================
dialog --title "Готово" --msgbox "\nУстановка успешно завершена!\n\nВсе сервисы установлены и запущены.\n" 15 100

# ==========================================
# 7. Окно с информацией об установке - МАКСИМАЛЬНОЕ
# ==========================================
dialog --title "Информация об установке" \
       --backtitle "Docker Installer - Данные доступа" \
       --cr-wrap \
       --msgbox "========================================\nУСТАНОВЛЕНЫ СЛЕДУЮЩИЕ СЕРВИСЫ:\n========================================${service_info}\n\n========================================\nВАЖНО: Сохраните эти данные!\n========================================" 40 120

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
