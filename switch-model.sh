#!/usr/bin/env bash
# Переключение провайдера модели.
#
#   ./switch-model.sh kimi              -> kimi-k3
#   ./switch-model.sh kimi kimi-k2.6    -> явная модель
#   ./switch-model.sh deepseek          -> deepseek-v4-pro
#   ./switch-model.sh status            -> текущее состояние и ключи
#
# Второй экземпляр: HX=2 ./switch-model.sh kimi
#
# Ключи берутся из .env: KIMI_API_KEY / DEEPSEEK_API_KEY.
# config.yaml читается при старте, поэтому в конце нужен restart.
set -euo pipefail

# Какой экземпляр переключаем: 1 (твой) или 2 (второго пользователя)
N="${HX:-1}"
if [ "$N" = "2" ]; then C=hx-hermes2; SVC=hermes2; else C=hx-hermes; SVC=hermes; fi

case "${1:-}" in
  kimi)
    provider=kimi
    model="${2:-kimi-k3}"
    base_url="https://api.moonshot.ai/v1"   # .cn недоступен с ряда хостов
    ;;
  deepseek)
    provider=deepseek
    model="${2:-deepseek-v4-pro}"
    base_url="https://api.deepseek.com/v1"
    ;;
  status)
    docker exec "$C" hermes status 2>&1 | grep -iE "model:|provider:|✓|✗" | head -12
    exit 0
    ;;
  *)
    cat >&2 <<EOF
usage: $0 {kimi|deepseek} [model]
       $0 status

модели:
  kimi      kimi-k3 (1M контекст), kimi-k2.7-code, kimi-k2.7-code-highspeed, kimi-k2.6
  deepseek  deepseek-v4-pro, deepseek-v4-flash
EOF
    exit 1
    ;;
esac

docker exec "$C" hermes config set model.provider "$provider"
docker exec "$C" hermes config set model.default  "$model"
docker exec "$C" hermes config set model.base_url "$base_url"

docker compose restart "$SVC" >/dev/null
echo "→ $C: переключено на $provider / $model, контейнер перезапущен"
