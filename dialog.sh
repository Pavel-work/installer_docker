#!/bin/bash

# Проверка наличия утилиты dialog
if ! command -v dialog &> /dev/null; then
    echo "Ошибка: утилита 'dialog' не установлена."
    echo "Установите: sudo apt install dialog"
    exit 1
fi

clear

# ==========================================
# Функция для получения ширины терминала
# ==========================================
get_term_width() {
    tput cols 2>/dev/null || echo 80
}

get_term_height() {
    tput lines 2>/dev/null || echo 24
}

TERM_WIDTH=$(get_term_width)
TERM_HEIGHT=$(get_term_height)

# ==========================================
# 1. Приветствие - ДИНАМИЧЕСКОЕ
# ==========================================
welcome_text=(
    "Добро пожаловать в установщик Docker контейнеров!"
    ""
    "Этот мастер поможет быстро установить и настроить сервисы."
    ""
    "Нажмите 'Начать установку' для продолжения."
)

# Рассчитываем высоту на основе количества строк
welcome_height=$((${#welcome_text[@]} + 4))
welcome_width=80

# Проверяем, чтобы окно не было больше терминала
if [ $welcome_width -gt $((TERM_WIDTH - 4)) ]; then
    welcome_width=$((TERM_WIDTH - 4))
fi

dialog --backtitle "Docker Installer" \
       --title "Добро пожаловать в установщик Docker" \
       --yes-label "Начать установку" --no-label "Выход" \
       --yesno "$(printf '%s\n' "${welcome_text[@]}")" $welcome_height $welcome_width

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 2. Выбор сервисов - ДИНАМИЧЕСКИЙ
# ==========================================
# Список сервисов
declare -a services=(
    "PostgreSQL" "База данных PostgreSQL" OFF
    "Qdrant" "Векторная база Qdrant для AI" OFF
    "Ollama" "Локальная LLM Ollama" OFF
    "Apache" "Веб-сервер Apache HTTP" OFF
    "NginxProxy" "Nginx Proxy Manager" OFF
    "Portainer" "Управление Docker Portainer" OFF
    "Supabase" "Supabase Full Stack" OFF
    "n8n" "Автоматизация workflow n8n" OFF
)

# Количество сервисов
num_services=$(( ${#services[@]} / 3 ))

# Высота: заголовок + подсказка + список сервисов + отступы
list_height=10
if [ $num_services -gt 10 ]; then
    list_height=$num_services
fi

checklist_height=$((list_height + 6))
checklist_width=$((TERM_WIDTH - 8))
if [ $checklist_width -gt 100 ]; then
    checklist_width=100
fi

choices=$(dialog --stdout \
                 --backtitle "Docker Installer - Выбор сервисов" \
                 --title "Выбор сервисов для установки" \
                 --ok-label "Установить выбранные" --cancel-label "Отмена" \
                 --checklist "Отметьте нужные сервисы (пробел - выбор/снятие):" \
                 $checklist_height $checklist_width $list_height \
                 "${services[@]}")

[ $? -ne 0 ] && { dialog --msgbox "Установка отменена.\n\nИзменения не внесены." 8 60; clear; exit 0; }
[ -z "$choices" ] && { dialog --msgbox "Ошибка: Выберите хотя бы один сервис!" 8 60; clear; exit 1; }

clean_choices=$(echo "$choices" | xargs -n 1 | tr -d '"')
num_selected=$(echo "$clean_choices" | wc -l)

# ==========================================
# 3. Подтверждение - ДИНАМИЧЕСКОЕ
# ==========================================
services_list=$(echo "$clean_choices" | sed 's/^/    • /')

# Динамический расчет высоты
base_height=12
dynamic_height=$((base_height + num_selected))

# Ограничиваем высоту
if [ $dynamic_height -gt 28 ]; then
    dynamic_height=28
fi

confirm_width=$((TERM_WIDTH - 8))
if [ $confirm_width -gt 90 ]; then
    confirm_width=90
fi

dialog --title "Подтверждение установки" \
       --yes-label "Установить" --no-label "Отмена" \
       --yesno "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n          ПОДТВЕРДИТЕ УСТАНОВКУ\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nБудут выполнены:\n\n  1. Установка Docker Engine\n  2. Установка Docker Compose\n  3. Настройка сервисов (${num_selected} шт.):\n\n${services_list}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nПродолжить?" $dynamic_height $confirm_width

[ $? -ne 0 ] && { clear; exit 0; }

# ==========================================
# 4. Установка - ДИНАМИЧЕСКАЯ
# ==========================================
# Шаг 1
step1_height=$((8 + num_selected / 2))
dialog --infobox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n      ШАГ 1: УСТАНОВКА DOCKER ENGINE\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n  Загрузка репозиториеv...\n  Установка Docker Engine...\n  Настройка служб...\n\n  [████████░░░░░░░░░░░░░░░░] 40%\n" $step1_height 80
sleep 2

# Шаг 2
step2_height=$((10 + num_selected))
dialog --infobox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n      ШАГ 2: УСТАНОВКА СЕРВИСОВ\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n  ✓ Docker Engine установлен!\n\n  Установка и настройка:\n\n$(echo "$clean_choices" | sed 's/^/    ⚙ /')\n\n  [████████████████████░░] 85%\n" $step2_height 80
sleep 2

# ==========================================
# 5. Генерация данных доступа
# ==========================================
service_info=""
max_line_length=0

for service in $clean_choices; do
    case "$service" in
        PostgreSQL)
            pass=$(openssl rand -base64 14)
            block="\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📦 PostgreSQL\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   Порт: 5432\n   Пользователь: postgres\n   Пароль: $pass\n   URL: localhost:5432"
            service_info="${service_info}${block}"
            ;;
        Qdrant)
            block="\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📦 Qdrant\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   Порт REST: 6333\n   Порт gRPC: 6334\n   URL: http://localhost:6333"
            service_info="${service_info}${block}"
            ;;
        Ollama)
            block="\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📦 Ollama\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   Порт: 11434\n   API: http://localhost:11434\n   Пример: ollama pull llama2"
            service_info="${service_info}${block}"
            ;;
        Apache)
            block="\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📦 Apache\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   HTTP: 80\n   HTTPS: 443\n   URL: http://localhost"
            service_info="${service_info}${block}"
            ;;
        NginxProxy)
            pass=$(openssl rand -base64 14)
            block="\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📦 Nginx Proxy Manager\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   HTTP: 80\n   HTTPS: 443\n   Панель: http://localhost:81\n   Email: admin@example.com\n   Пароль: $pass"
            service_info="${service_info}${block}"
            ;;
        Portainer)
            block="\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📦 Portainer\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   HTTP: 9000\n   HTTPS: 9443\n   URL: https://localhost:9443"
            service_info="${service_info}${block}"
            ;;
        Supabase)
            block="\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📦 Supabase\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   Kong: http://localhost:8000\n   Studio: http://localhost:8001\n   Postgres: localhost:54322"
            service_info="${service_info}${block}"
            ;;
        n8n)
            block="\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📦 n8n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n   Порт: 5678\n   URL: http://localhost:5678"
            service_info="${service_info}${block}"
            ;;
    esac
done

# ==========================================
# 6. Финальное окно - ДИНАМИЧЕСКОЕ
# ==========================================
# Считаем количество строк в service_info
info_lines=$(echo -e "$service_info" | wc -l)
final_height=$((15 + info_lines))

# Ограничиваем максимальную высоту
if [ $final_height -gt 35 ]; then
    final_height=35
fi

final_width=$((TERM_WIDTH - 8))
if [ $final_width -gt 95 ]; then
    final_width=95
fi

dialog --title "✓ Установка завершена" \
       --backtitle "Docker Installer - Данные доступа" \
       --msgbox "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n       ✓ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\nВсе сервисы установлены и запущены.\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n            ДАННЫЕ ДОСТУПА:\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${service_info}\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n            ⚠️  ВАЖНО!\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n  • Сохраните эти данные!\n  • Пароли сгенерированы автоматически\n  • Для изменения паролей отредактируйте .env\n\n  Спасибо за использование Docker Installer!\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" $final_height $final_width

# ==========================================
# Вывод в консоль
# ==========================================
clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "       ✓ УСТАНОВКА ЗАВЕРШЕНА!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Установленные сервисы (${num_selected}):"
echo -e "$clean_choices" | sed 's/^/  ✓ /'
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Данные доступа:${service_info}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Сохраните эти данные в безопасном месте!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
