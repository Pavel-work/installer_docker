#!/bin/bash

# Проверка наличия утилиты dialog
if ! command -v dialog &> /dev/null; then
    echo "Ошибка: утилита 'dialog' не установлена."
    echo "Установите: sudo apt install dialog"
    exit 1
fi

clear

# ==========================================
# 1. Приветствие (14x81) - было 15x90
# ==========================================
dialog --backtitle "Docker Installer" \
       --title "Добро пожаловать в установщик Docker" \
       --yes-label "Начать установку" --no-label "Выход" \
       --yesno "Добро пожаловать в установщик Docker контейнеров!\n\nЭтот мастер поможет быстро установить и настроить сервисы.\n\nНажмите 'Начать установку' для продолжения." 14 81

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 2. Выбор сервисов (23x97) - было 25x108
# ==========================================
choices=$(dialog --stdout \
                 --backtitle "Docker Installer - Выбор сервисов" \
                 --title "Выбор сервисов" \
                 --ok-label "Установить выбранные" --cancel-label "Отмена" \
                 --checklist "Отметьте нужные сервисы (пробел - выбор):" 23 97 10 \
                 "PostgreSQL"   "База данных PostgreSQL" OFF \
                 "Qdrant"       "Векторная база Qdrant для AI" OFF \
                 "Ollama"       "Локальная LLM Ollama" OFF \
                 "Apache"       "Веб-сервер Apache HTTP" OFF \
                 "NginxProxy"   "Nginx Proxy Manager" OFF \
                 "Portainer"    "Управление Docker Portainer" OFF \
                 "Supabase"     "Supabase Full Stack" OFF \
                 "n8n"          "Автоматизация workflow n8n" OFF)

[ $? -ne 0 ] && { dialog --msgbox "Установка отменена.\n\nИзменения не внесены." 10 81; clear; exit 0; }
[ -z "$choices" ] && { dialog --msgbox "Ошибка: Выберите хотя бы один сервис!" 10 81; clear; exit 1; }

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')

# ==========================================
# 3. Подтверждение (16x81) - было 18x90
# ==========================================
dialog --title "Подтверждение установки" \
       --yes-label "Установить" --no-label "Отмена" \
       --yesno "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n         ПОДТВЕРДИТЕ УСТАНОВКУ\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nБудут выполнены:\n\n  1. Установка Docker Engine\n  2. Установка Docker Compose\n  3. Настройка сервисов:\n\n$(echo "$clean_choices" | sed 's/^/     • /')\n\nПродолжить установку?" 16 81

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 4. Установка (имитация) (12x81 / 13x81) - было 13x90 / 14x90
# ==========================================
dialog --infobox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n      ШАГ 1: УСТАНОВКА DOCKER\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n  Загрузка и установка Docker...\n  Настройка служб...\n\n  Пожалуйста, подождите.\n\n  [##########..................] 40%\n" 12 81
sleep 2

dialog --infobox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n      ШАГ 2: УСТАНОВКА СЕРВИСОВ\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n  ✓ Docker установлен!\n\n  Установка сервисов:\n\n$(echo "$clean_choices" | sed 's/^/     ⚙ /')\n\n  [####################......] 80%\n" 13 81
sleep 2

# ==========================================
# 5. Генерация данных
# ==========================================
service_info=""
for service in $clean_choices; do
    case "$service" in
        PostgreSQL)
            pass=$(openssl rand -base64 14)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 PostgreSQL"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   Порт: 5432"
            service_info="${service_info}\n   Пользователь: postgres"
            service_info="${service_info}\n   Пароль: $pass"
            service_info="${service_info}\n   URL: localhost:5432" ;;
        Qdrant)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Qdrant"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   Порт REST: 6333"
            service_info="${service_info}\n   Порт gRPC: 6334"
            service_info="${service_info}\n   URL: http://localhost:6333" ;;
        Ollama)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Ollama"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   Порт: 11434"
            service_info="${service_info}\n   API: http://localhost:11434"
            service_info="${service_info}\n   Пример: ollama pull llama2" ;;
        Apache)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Apache"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   HTTP: 80"
            service_info="${service_info}\n   HTTPS: 443"
            service_info="${service_info}\n   URL: http://localhost" ;;
        NginxProxy)
            pass=$(openssl rand -base64 14)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Nginx Proxy Manager"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   HTTP: 80"
            service_info="${service_info}\n   HTTPS: 443"
            service_info="${service_info}\n   Панель: http://localhost:81"
            service_info="${service_info}\n   Email: admin@example.com"
            service_info="${service_info}\n   Пароль: $pass" ;;
        Portainer)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Portainer"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   HTTP: 9000"
            service_info="${service_info}\n   HTTPS: 9443"
            service_info="${service_info}\n   URL: https://localhost:9443" ;;
        Supabase)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Supabase"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   Kong: http://localhost:8000"
            service_info="${service_info}\n   Studio: http://localhost:8001"
            service_info="${service_info}\n   Postgres: localhost:54322" ;;
        n8n)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 n8n"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   Порт: 5678"
            service_info="${service_info}\n   URL: http://localhost:5678" ;;
    esac
done

# ==========================================
# 6. Готово + Информация (25x97) - было 28x108
# ==========================================
dialog --title "✓ Установка завершена" \
       --backtitle "Docker Installer - Данные доступа" \
       --msgbox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n       ✓ УСТАНОВКА ЗАВЕРШЕНА!\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nВсе сервисы установлены и запущены.\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n            ДАННЫЕ ДОСТУПА:\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n            ⚠️  ВАЖНО!\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n  • Сохраните эти данные!\n  • Пароли сгенерированы автоматически\n  • Документация: /opt/docker/docs\n\n  Спасибо за использование!\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" 25 97

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "       ✓ УСТАНОВКА ЗАВЕРШЕНА!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Установленные сервисы:"
echo -e "$clean_choices" | sed 's/^/  ✓ /'
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Данные доступа:${service_info}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Сохраните эти данные в безопасном месте!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
