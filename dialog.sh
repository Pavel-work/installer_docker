#!/bin/bash

# Проверка наличия утилиты dialog
if ! command -v dialog &> /dev/null; then
    echo "Ошибка: утилита 'dialog' не установлена."
    echo "Установите: sudo apt install dialog"
    exit 1
fi

clear

# ==========================================
# 1. Приветствие (17x100) - было 12x72
# ==========================================
dialog --backtitle "Docker Installer" \
       --title "Добро пожаловать в установщик Docker контейнеров" \
       --yes-label "Начать установку" --no-label "Выход" \
       --yesno "Добро пожаловать в интерактивный установщик Docker контейнеров!\n\nЭтот мастер поможет вам быстро установить и настроить необходимые сервисы.\n\nНажмите 'Начать установку' для продолжения." 17 100

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 2. Выбор сервисов (28x120) - было 20x86
# ==========================================
choices=$(dialog --stdout \
                 --backtitle "Docker Installer - Выбор сервисов для установки" \
                 --title "Выбор сервисов" \
                 --ok-label "Установить выбранные" --cancel-label "Отмена" \
                 --checklist "Отметьте нужные сервисы для установки (пробел - выбор/снятие):" 28 120 12 \
                 "PostgreSQL"   "База данных PostgreSQL - мощная реляционная СУБД" OFF \
                 "Qdrant"       "Векторная база данных Qdrant для AI/ML" OFF \
                 "Ollama"       "Локальная LLM Ollama - запуск нейросетей" OFF \
                 "Apache"       "Веб-сервер Apache HTTP Server" OFF \
                 "NginxProxy"   "Nginx Proxy Manager - управление прокси" OFF \
                 "Portainer"    "Portainer - удобное управление Docker" OFF \
                 "Supabase"     "Supabase Full Stack - Firebase альтернатива" OFF \
                 "n8n"          "n8n - автоматизация workflow и интеграции" OFF)

[ $? -ne 0 ] && { dialog --msgbox "Установка отменена пользователем.\n\nНикакие изменения не были внесены в систему." 12 100; clear; exit 0; }
[ -z "$choices" ] && { dialog --msgbox "Ошибка: Вы не выбрали ни одного сервиса!\n\nПожалуйста, выберите хотя бы один сервис для установки." 12 100; clear; exit 1; }

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')

# ==========================================
# 3. Подтверждение (20x100) - было 14x72
# ==========================================
dialog --title "Подтверждение установки" \
       --yes-label "Установить" --no-label "Отмена" \
       --yesno "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n         ПОДТВЕРДИТЕ УСТАНОВКУ\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nБудут выполнены следующие действия:\n\n  1. Установка Docker Engine (последняя стабильная версия)\n  2. Установка Docker Compose\n  3. Настройка и запуск выбранных сервисов:\n\n$(echo "$clean_choices" | sed 's/^/     • /')\n\nСистема будет автоматически настроена.\n\nПродолжить установку?" 20 100

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 4. Установка (имитация) (14x100) - было 10x72
# ==========================================
dialog --infobox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n      ШАГ 1 ИЗ 2: УСТАНОВКА DOCKER ENGINE\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n  Загрузка репозиториев Docker...\n  Установка Docker Engine и Docker Compose...\n  Настройка служб Docker...\n\n  Пожалуйста, подождите. Это может занять несколько минут.\n\n  [##########..................] 40%\n" 14 100
sleep 2

dialog --infobox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n      ШАГ 2 ИЗ 2: УСТАНОВКА СЕРВИСОВ\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n  ✓ Docker Engine успешно установлен!\n\n  Установка и настройка выбранных сервисов:\n\n$(echo "$clean_choices" | sed 's/^/     ⚙️  /')\n\n  [####################......] 80%\n" 16 100
sleep 2

# ==========================================
# 5. Генерация данных
# ==========================================
service_info=""
for service in $clean_choices; do
    case "$service" in
        PostgreSQL)
            pass=$(openssl rand -base64 14)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 PostgreSQL - Реляционная база данных"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   Порт: 5432"
            service_info="${service_info}\n   Пользователь: postgres"
            service_info="${service_info}\n   Пароль: $pass"
            service_info="${service_info}\n   Подключение: psql -h localhost -U postgres"
            service_info="${service_info}\n   URL: localhost:5432" ;;
        Qdrant)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Qdrant - Векторная база данных"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   Порт REST: 6333"
            service_info="${service_info}\n   Порт gRPC: 6334"
            service_info="${service_info}\n   Web UI: http://localhost:6333/dashboard"
            service_info="${service_info}\n   API: http://localhost:6333" ;;
        Ollama)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Ollama - Локальная LLM"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   Порт: 11434"
            service_info="${service_info}\n   API: http://localhost:11434"
            service_info="${service_info}\n   Пример: ollama pull llama2"
            service_info="${service_info}\n   Документация: https://ollama.ai" ;;
        Apache)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Apache - Веб-сервер"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   HTTP Порт: 80"
            service_info="${service_info}\n   HTTPS Порт: 443"
            service_info="${service_info}\n   URL: http://localhost"
            service_info="${service_info}\n   Корневая директория: /var/www/html" ;;
        NginxProxy)
            pass=$(openssl rand -base64 14)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Nginx Proxy Manager"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   HTTP Порт: 80"
            service_info="${service_info}\n   HTTPS Порт: 443"
            service_info="${service_info}\n   Admin Panel: http://localhost:81"
            service_info="${service_info}\n   Email: admin@example.com"
            service_info="${service_info}\n   Пароль: $pass" ;;
        Portainer)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Portainer - Управление Docker"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   HTTP Порт: 9000"
            service_info="${service_info}\n   HTTPS Порт: 9443"
            service_info="${service_info}\n   URL: https://localhost:9443"
            service_info="${service_info}\n   Создайте admin при первом входе" ;;
        Supabase)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 Supabase (Full Stack)"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   Kong API: http://localhost:8000"
            service_info="${service_info}\n   Studio: http://localhost:8001"
            service_info="${service_info}\n   Auth: http://localhost:9999"
            service_info="${service_info}\n   Postgres: localhost:54322"
            service_info="${service_info}\n   S3 Storage: localhost:9000" ;;
        n8n)
            service_info="${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n📦 n8n - Автоматизация workflow"
            service_info="${service_info}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            service_info="${service_info}\n   Порт: 5678"
            service_info="${service_info}\n   URL: http://localhost:5678"
            service_info="${service_info}\n   Создайте пользователя при первом входе"
            service_info="${service_info}\n   Документация: https://docs.n8n.io" ;;
    esac
done

# ==========================================
# 6. Готово + Информация (31x120) - было 22x86
# ==========================================
dialog --title "✓ Установка завершена успешно" \
       --backtitle "Docker Installer - Данные доступа к сервисам" \
       --msgbox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n           ✓ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nВсе сервисы установлены, настроены и запущены.\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n                    ДАННЫЕ ДОСТУПА:\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n                    ⚠️  ВАЖНО!\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n  • Сохраните эти данные в безопасном месте!\n  • Пароли были сгенерированы автоматически\n  • Для изменения паролей отредактируйте .env файлы\n  • Документация: /opt/docker/docs\n\n  Спасибо за использование Docker Installer!\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" 31 120

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "           ✓ УСТАНОВКА ЗАВЕРШЕНА!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Установленные сервисы:"
echo -e "$clean_choices" | sed 's/^/  ✓ /'
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Данные доступа:${service_info}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Сохраните эти данные в безопасном месте!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
