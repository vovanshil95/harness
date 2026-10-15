#!/usr/bin/env bash
# Добавление Telegram-бота Hermes для существующего пользователя LiveSync.
# Вход: nick (как в add-user.sh), bot-token (от @BotFather), allowed-users (id через запятую).
# Создаёт контейнер hx-hermes-<nick>, монтирует vault-<nick>, ставит deepseek-v4-flash
# и готовит Google Calendar MCP (credentials.json + конфиг). OAuth-вход — отдельно через
# gcal-auth.sh <nick>.
#
# Использование:
#   ./add-hermes-user.sh vasilisa 123456:AAAA... 111111111,222222222
set -euo pipefail

SERVER="${HARNESS_SERVER:-remote.unicort.ru}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NICK="${1:-}"
TOKEN="${2:-}"
USERS="${3:-}"

if [[ -z "$NICK" || -z "$TOKEN" || -z "$USERS" ]]; then
  echo "Использование: $0 <nick> <bot-token> <allowed-users>" >&2
  echo "  nick          — как в add-user.sh (должен уже существовать)" >&2
  echo "  bot-token     — от @BotFather" >&2
  echo "  allowed-users — Telegram user id через запятую" >&2
  exit 1
fi
if [[ ! "$NICK" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  echo "Ошибка: nick должен быть на английском, только a-z0-9_-." >&2
  exit 1
fi

VAULT="vault-${NICK}"
DATA="hermes-${NICK}-data"
CONTAINER="hx-hermes-${NICK}"

echo "==> Проверяю, что волт $VAULT существует..."
ssh "$SERVER" "test -d ~/harness/$VAULT && echo 'OK: волт найден' || { echo 'Ошибка: волт $VAULT не найден. Сначала ./add-user.sh $NICK' >&2; exit 1; }"

echo "==> Создаю каталог данных, копирую Google credentials и поднимаю контейнер..."
ssh "$SERVER" NICK="$NICK" TOKEN="$TOKEN" USERS="$USERS" \
  VAULT="$VAULT" DATA="$DATA" CONTAINER="$CONTAINER" \
  'bash -s' <<'REMOTE'
set -euo pipefail
H=~/harness
mkdir -p "$H/$DATA/gcal"
chmod 700 "$H/$DATA"
cp "$H/hermes-data/gcal/credentials.json" "$H/$DATA/gcal/credentials.json"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --restart on-failure:3 \
  --add-host "api.telegram.org:149.154.167.220" \
  -e PUID=1000 -e PGID=1000 -e HERMES_UID=1000 -e HERMES_GID=1000 \
  -e TELEGRAM_BOT_TOKEN="$TOKEN" -e TELEGRAM_ALLOWED_USERS="$USERS" \
  --env-file "$H/.env" \
  -v "$H/$DATA:/opt/data" \
  -v "$H/$VAULT:/opt/data/vault" \
  --memory 1536m --memory-swap 1536m --pids-limit 512 --cpus 1.5 \
  nousresearch/hermes-agent:latest gateway run >/dev/null
echo "OK: контейнер запущен"
REMOTE

echo "==> Жду инициализации и настраиваю модель + Google Calendar MCP..."
ssh "$SERVER" CONTAINER="$CONTAINER" 'bash -s' <<'REMOTE'
set -euo pipefail
sleep 25
hermes_set() { docker exec "$CONTAINER" hermes config set "$@"; }
hermes_set model.provider deepseek
hermes_set model.default deepseek-v4-flash
hermes_set model.base_url https://api.deepseek.com/v1
hermes_set mcp_servers.gcal.command npx
hermes_set 'mcp_servers.gcal.args' '["-y","mcp-google-calendar"]'
hermes_set 'mcp_servers.gcal.env' '{"CREDENTIALS_PATH":"/opt/data/gcal/credentials.json"}'
docker restart "$CONTAINER" >/dev/null
echo "OK: модель deepseek-v4-flash + MCP gcal настроены, контейнер перезапущен"
REMOTE

echo
echo "=== Пользователь '$NICK' добавлен в Hermes ==="
echo "контейнер:  $CONTAINER"
echo "модель:     deepseek-v4-flash"
echo "волт:       $VAULT (примонтирован)"
echo
echo "Осталось вручную:"
echo "1. Авторизовать Google Calendar: ./gcal-auth.sh $NICK"
echo "2. В Google Cloud Console убедиться, что gmail пользователя добавлен в"
echo "   OAuth consent screen -> Test users (иначе будет 403 access_denied)."
echo
echo "После авторизации попросить пользователя написать /reload_mcp в чате бота."
