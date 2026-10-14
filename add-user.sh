#!/usr/bin/env bash
# Добавление нового пользователя LiveSync одной командой.
# Вход: nick (английский, a-z0-9-). Выход: passphrase + setup-URI.
# На сервере создаёт базу CouchDB, волт, каталог данных и контейнер hx-livesync-<nick>.
#
# Использование:
#   ./add-user.sh <nick>
#   ./add-user.sh alice
set -euo pipefail

SERVER="${HARNESS_SERVER:-remote.unicort.ru}"
PUBLIC_COUCHDB_URI="${HARNESS_COUCHDB_URI:-https://couchdb.5-8-9-221.sslip.io}"
HARNESS_DIR='~/harness'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NICK="${1:-}"
if [[ -z "$NICK" ]]; then
  echo "Использование: $0 <nick>" >&2
  exit 1
fi
if [[ ! "$NICK" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  echo "Ошибка: nick должен быть на английском, только a-z0-9_- (без пробелов и спецсимволов)." >&2
  exit 1
fi

DB="obsidian-${NICK}"
VAULT="vault-${NICK}"
DATA="livesync-${NICK}-data"
CONTAINER="hx-livesync-${NICK}"

echo "==> Читаю учётные данные CouchDB с сервера..."
COUCHDB_USER="$(ssh "$SERVER" "grep '^COUCHDB_USER=' $HARNESS_DIR/.env | cut -d= -f2")"
COUCHDB_PASSWORD="$(ssh "$SERVER" "grep '^COUCHDB_PASSWORD=' $HARNESS_DIR/.env | cut -d= -f2")"
if [[ -z "$COUCHDB_USER" || -z "$COUCHDB_PASSWORD" ]]; then
  echo "Ошибка: не нашёл COUCHDB_USER/COUCHDB_PASSWORD в $HARNESS_DIR/.env" >&2
  exit 1
fi

PASSPHRASE="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-18)"

# Настройки серверного клиента (внутренний URI hx-couchdb).
SERVER_SETTINGS="{\"couchDB_URI\":\"http://hx-couchdb:5984\",\"couchDB_USER\":\"$COUCHDB_USER\",\"couchDB_PASSWORD\":\"$COUCHDB_PASSWORD\",\"couchDB_DBNAME\":\"$DB\",\"liveSync\":true,\"syncOnSave\":true,\"syncOnStart\":true,\"encrypt\":true,\"passphrase\":\"$PASSPHRASE\",\"usePluginSync\":false,\"usePluginSyncV2\":true,\"isConfigured\":true}"

echo "==> Создаю на сервере: база $DB, волт $VAULT, контейнер $CONTAINER..."
SETTINGS_B64="$(printf '%s' "$SERVER_SETTINGS" | base64 | tr -d '\n')"
ssh "$SERVER" \
  DB="$DB" VAULT="$VAULT" DATA="$DATA" CONTAINER="$CONTAINER" \
  SETTINGS_B64="$SETTINGS_B64" CU="$COUCHDB_USER" CP="$COUCHDB_PASSWORD" \
  'bash -s' <<'REMOTE'
set -euo pipefail
H=~/harness
if curl -s -u "$CU:$CP" "http://127.0.0.1:5984/$DB" | grep -q '"db_name"'; then
  echo "Ошибка: база $DB уже существует. Выбери другой nick." >&2
  exit 1
fi
curl -s -X PUT -u "$CU:$CP" "http://127.0.0.1:5984/$DB" >/dev/null
mkdir -p "$H/$VAULT" "$H/$DATA/.livesync"
printf '%s' "$SETTINGS_B64" | base64 -d > "$H/$DATA/.livesync/settings.json"
sudo chown -R 1000:1000 "$H/$VAULT" "$H/$DATA"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --network harness_default --restart on-failure:3 \
  --user 1000:1000 \
  -v "$H/$DATA:/data" -v "$H/$VAULT:/vault" \
  --memory 512m --pids-limit 256 --cpus 1.0 \
  livesync-cli --vault /vault daemon >/dev/null
echo "OK: база и контейнер созданы"
REMOTE

echo "==> Генерирую setup-URI..."
URI="$(cd "$SCRIPT_DIR" && node tools/gen-setup-uri.mjs \
  --dbname "$DB" --passphrase "$PASSPHRASE" \
  --couchdb-uri "$PUBLIC_COUCHDB_URI" \
  --couchdb-user "$COUCHDB_USER" --couchdb-password "$COUCHDB_PASSWORD")"

mkdir -p "$SCRIPT_DIR/users"
OUT="$SCRIPT_DIR/users/$NICK.txt"
{
  echo "nick:       $NICK"
  echo "database:   $DB"
  echo "container:  $CONTAINER"
  echo "passphrase: $PASSPHRASE"
  echo "setup-uri:  $URI"
} > "$OUT"

printf '%s' "$URI" | pbcopy

echo
echo "=== Пользователь '$NICK' создан ==="
echo "database:   $DB"
echo "passphrase: $PASSPHRASE"
echo
echo "setup-URI (скопирован в буфер обмена, сохранён в users/$NICK.txt):"
echo "$URI"
