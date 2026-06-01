```bash
curl -fsSL "https://raw.githubusercontent.com/Pavel-work/installer_docker/main/install.sh" | sudo bash -s
```
.
.
.
.
.
______________________________________________________________________________________________________________________________________________________________________________________________________________________
ОТ ОПУСА 
```bash
curl -fsSL "https://raw.githubusercontent.com/Pavel-work/installer_docker/main/ot_opusa" | sudo bash -s
```
```bash
Проверка после установки
# Cloudflared подключился?
docker logs cloudflared | tail -20
# Должно быть: "Registered tunnel connection connIndex=0 ..."

# Сеть видит все сервисы?
docker exec cloudflared wget -qO- http://n8n:5678 | head -5
docker exec cloudflared wget -qO- http://supabase-kong:8000 | head -5

# Все контейнеры в одной сети?
docker network inspect internal_network | grep -A1 Containers
```
Что делать после установки (для пользователя)
Token-режим:

Зайти в dash.cloudflare.com → Zero Trust → Networks → Tunnels
Выбрать свой тоннель → вкладка Public Hostnames
Add a public hostname:
Subdomain: n8n, Domain: ваш домен
Service: HTTP, URL: n8n:5678 (имя контейнера + порт)
Повторить для каждого нужного сервиса
Config-режим:
Маршруты уже в config.yml, но нужно создать DNS-записи:

```bash
 docker exec cloudflared cloudflared tunnel route dns <tunnel-name> n8n.example.com
docker exec cloudflared cloudflared tunnel route dns <tunnel-name> studio.example.com
```
(или вручную CNAME в DNS Cloudflare: n8n → <TUNNEL_ID>.cfargotunnel.com)

Файлы и данные
Путь
Назначение
/root/server-setup/cloudflared/config.yml
Конфиг тоннеля (config-режим)
/root/server-setup/cloudflared/<ID>.json
Credentials тоннеля
/root/server-setup/.env
Все env-переменные
/root/.server-setup-state/params.env
Параметры (base64)
/var/log/install.log
Полный лог установки
