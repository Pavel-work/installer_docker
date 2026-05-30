#!/bin/bash

# Проверка наличия утилиты dialog
if ! command -v dialog &> /dev/null; then
    echo "Ошибка: утилита 'dialog' не установлена."
    echo "Установите: sudo apt install dialog"
    exit 1
fi

clear

# ==========================================
# 1. Приветствие (8x50)
# ==========================================
dialog --backtitle "Docker Installer" \
       --title "Добро пожаловать" \
       --yes-label "Начать" --no-label "Выход" \
       --yesno "Добро пожаловать!\n\nНажмите 'Начать'." 8 50

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 2. Выбор сервисов (14x60)
# ==========================================
choices=$(dialog --stdout \
                 --backtitle "Docker Installer" \
                 --title "Выбор сервисов" \
                 --ok-label "Установить" --cancel-label "Отмена" \
                 --checklist "Отметьте сервисы (пробел):" 14 60 6 \
                 "PostgreSQL" "PostgreSQL" OFF \
                 "Qdrant" "Qdrant" OFF \
                 "Ollama" "Ollama" OFF \
                 "Apache" "Apache" OFF \
                 "NginxProxy" "Nginx Proxy" OFF \
                 "Portainer" "Portainer" OFF \
                 "Supabase" "Supabase" OFF \
                 "n8n" "n8n" OFF)

[ $? -ne 0 ] && { dialog --msgbox "Отменено" 6 50; clear; exit 0; }
[ -z "$choices" ] && { dialog --msgbox "Выберите хотя бы один сервис!" 6 50; clear; exit 1; }

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')

# ==========================================
# 3. Подтверждение (10x50)
# ==========================================
dialog --title "Подтверждение" \
       --yes-label "Да" --no-label "Нет" \
       --yesno "Установить:\n- Docker\n$(echo "$clean_choices" | sed 's/^/- /')\n\nПродолжить?" 10 50

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 4. Установка (имитация)
# ==========================================
dialog --infobox "Установка Docker..." 6 50; sleep 1
dialog --infobox "Установка сервисов..." 6 50; sleep 1

# ==========================================
# 5. Генерация данных
# ==========================================
service_info=""
for service in $clean_choices; do
    case "$service" in
        PostgreSQL)
            pass=$(openssl rand -base64 8)
            service_info="${service_info}\nPostgreSQL: port 5432, pass: $pass" ;;
        Qdrant)
            service_info="${service_info}\nQdrant: http://localhost:6333" ;;
        Ollama)
            service_info="${service_info}\nOllama: http://localhost:11434" ;;
        Apache)
            service_info="${service_info}\nApache: http://localhost" ;;
        NginxProxy)
            pass=$(openssl rand -base64 8)
            service_info="${service_info}\nNginx Proxy: panel :81, pass: $pass" ;;
        Portainer)
            service_info="${service_info}\nPortainer: https://localhost:9443" ;;
        Supabase)
            service_info="${service_info}\nSupabase: Studio :8001" ;;
        n8n)
            service_info="${service_info}\nn8n: http://localhost:5678" ;;
    esac
done

# ==========================================
# 6. Готово + Информация (15x60)
# ==========================================
dialog --msgbox "✓ Установка завершена!\n\nДанные доступа:${service_info}\n\nСохраните их!" 15 60

clear
echo "✓ Готово! Сервисы: $clean_choices"
echo -e "Данные:$service_info"
