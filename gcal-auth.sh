#!/usr/bin/env bash
# Авторизация Google Calendar для пользователя Hermes (headless OAuth, две фазы).
# Генерирует ссылку, ждёт код от пользователя, сохраняет токен.
# OAuth-танец выполняется внутри контейнера (там уже есть google-auth-oauthlib).
#
# Использование:
#   ./gcal-auth.sh <nick>
set -euo pipefail

SERVER="${HARNESS_SERVER:-remote.unicort.ru}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NICK="${1:-}"
if [[ -z "$NICK" ]]; then
  echo "Использование: $0 <nick>" >&2
  exit 1
fi
if [[ ! "$NICK" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  echo "Ошибка: nick должен быть на английском, только a-z0-9_-." >&2
  exit 1
fi

CONTAINER="hx-hermes-${NICK}"
PY="/opt/hermes/.venv/bin/python"

echo "==> Кладу auth-gcal.py в данные пользователя..."
scp "$SCRIPT_DIR/tools/auth-gcal.py" "$SERVER:~/harness/hermes-${NICK}-data/auth-gcal.py" >/dev/null

echo "==> Генерирую ссылку авторизации..."
URL="$(ssh "$SERVER" "docker exec $CONTAINER $PY /opt/data/auth-gcal.py /opt/data/gcal url")"

echo
echo "Открой эту ссылку в браузере и войди в Google-аккаунт пользователя:"
echo "$URL"
echo
echo "После разрешения доступа браузер редиректнёт на http://localhost:3420/?..."
echo "Страница не загрузится — это нормально. Скопируй весь URL из адресной строки:"
read -r -p "redirect URL: " CODE

ssh "$SERVER" "docker exec $CONTAINER $PY /opt/data/auth-gcal.py /opt/data/gcal finish '$CODE'"

echo
echo "Готово. Попроси пользователя написать /reload_mcp в чате бота — появятся mcp__gcal__* инструменты."
