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
# 1. Окно приветствия
# ==========================================
dialog --backtitle "Docker Installer" \
       --title "Добро пожаловать" \
       --yes-label "Начать" \
       --no-label "Выход" \
       --yesno "Добро пожаловать в установщик Docker контейнеров!\n\nНажмите 'Начать', чтобы продолжить." 10 50

if [ $? -ne 0 ]; then
    clear
    exit 0
fi

# ==========================================
# 2. Окно выбора сервисов (Checklist)
# ==========================================
choices=$(dialog --stdout \
                 --backtitle "Docker Installer" \
                 --title "Выбор сервисов" \
                 --ok-label "Установить" \
                 --cancel-label "Отмена" \
                 --checklist "Выберите какие сервисы хотите установить:" 20 60 8 \
                 "PostgreSQL" "PostgreSQL" OFF \
                 "Qdrant" "Qdrant" OFF \
                 "Ollama" "Ollama" OFF \
                 "Apache" "Apache" OFF \
                 "NginxProxy" "Nginx Proxy Manager" OFF \
                 "Portainer" "Portainer" OFF \
                 "Supabase" "Supabase (Full)" OFF \
                 "n8n" "n8n" OFF)

if [ $? -ne 0 ]; then
    dialog --title "Отмена" --msgbox "Установка отменена." 7 40
    clear
    exit 0
fi

if [ -z "$choices" ]; then
    dialog --title "Ошибка" --msgbox "Вы не выбрали ни одного сервиса!\nУстановка прервана." 9 40
    clear
    exit 1
fi

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')

# ==========================================
# 3. Окно подтверждения перед установкой
# ==========================================
dialog --title "Подтверждение" \
       --yes-label "Установить" \
       --no-label "Отмена" \
       --yesno "Будут выполнены следующие действия:\n\n1. Установка Docker\n2. Установка контейнеров:\n\n$clean_choices\n\nПродолжить?" 18 50

if [ $? -ne 0 ]; then
    clear
    exit 0
fi

# ==========================================
# 4. Имитация процесса установки (Оболочка)
# ==========================================
dialog --title "Установка" \
       --infobox "Сначала устанавливается Docker...\nПожалуйста, подождите." 8 50
sleep 2

dialog --title "Установка" \
       --infobox "Docker установлен!\nУстанавливаем выбранные контейнеры:\n\n$clean_choices" 14 50
sleep 2

# ==========================================
# 5. Генерация данных доступа
# ==========================================
service_info=""

for service in $clean_choices; do
    case "$service" in
        PostgreSQL)
            password=$(openssl rand -base64 12)
            service_info="${service_info}\nPostgreSQL"
            service_info="${service_info}\n  Порт: 5432"
            service_info="${service_info}\n  Пользователь: postgres"
            service_info="${service_info}\n  Пароль: ${password}"
            service_info="${service_info}\n  Подключение: psql -h localhost -U postgres\n"
            ;;
        Qdrant)
            service_info="${service_info}\nQdrant"
            service_info="${service_info}\n  Порт: 6333"
            service_info="${service_info}\n  REST API: http://localhost:6333"
            service_info="${service_info}\n  gRPC: localhost:6334\n"
            ;;
        Ollama)
            service_info="${service_info}\nOllama"
            service_info="${service_info}\n  Порт: 11434"
            service_info="${service_info}\n  API: http://localhost:11434"
            service_info="${service_info}\n  Модели: ollama pull llama2\n"
            ;;
        Apache)
            service_info="${service_info}\nApache"
            service_info="${service_info}\n  HTTP Порт: 80"
            service_info="${service_info}\n  HTTPS Порт: 443"
            service_info="${service_info}\n  URL: http://localhost\n"
            ;;
        NginxProxy)
            admin_password=$(openssl rand -base64 12)
            service_info="${service_info}\nNginx Proxy Manager"
            service_info="${service_info}\n  Порт: 80 (HTTP)"
            service_info="${service_info}\n  Порт: 443 (HTTPS)"
            service_info="${service_info}\n  Панель: http://localhost:81"
            service_info="${service_info}\n  Email: admin@example.com"
            service_info="${service_info}\n  Пароль: ${admin_password}\n"
            ;;
        Portainer)
            service_info="${service_info}\nPortainer"
            service_info="${service_info}\n  Порт: 9443 (HTTPS)"
            service_info="${service_info}\n  URL: https://localhost:9443"
            service_info="${service_info}\n  Создайте admin при первом входе\n"
            ;;
        Supabase)
            service_info="${service_info}\nSupabase (Full)"
            service_info="${service_info}\n  Kong API: http://localhost:8000"
            service_info="${service_info}\n  Studio: http://localhost:8001"
            service_info="${service_info}\n  Auth: http://localhost:9999"
            service_info="${service_info}\n  Postgres: localhost:54322\n"
            ;;
        n8n)
            service_info="${service_info}\nn8n"
            service_info="${service_info}\n  Порт: 5678"
            service_info="${service_info}\n  URL: http://localhost:5678"
            service_info="${service_info}\n  Создайте пользователя при первом входе\n"
            ;;
    esac
done

# ==========================================
# 6. Финальное окно "Готово"
# ==========================================
dialog --title "Готово" --msgbox "Установка успешно завершена!" 7 40

# ==========================================
# 7. Окно с информацией об установке
# ==========================================
dialog --title "Информация об установке" \
       --backtitle "Docker Installer" \
       --msgbox "Установленные сервисы и данные доступа:\n\n${service_info}\n\nВажно: сохраните эти данные!" 25 70

# Финальная очистка экрана
clear
echo "=========================================="
echo "Установка завершена!"
echo "=========================================="
echo ""
echo "Установленные сервисы:"
echo -e "$clean_choices" | sed 's/^/  - /'
echo ""
echo "Данные доступа:"
echo -e "$service_info"
echo ""
echo "=========================================="
