# harness

Telegram-бот на базе [Hermes Agent](https://github.com/NousResearch/hermes-agent) в Docker.
Работает как gateway: принимает сообщения в Telegram и отвечает через DeepSeek.

## Запуск

```bash
cp .env.example .env      # подставить реальные токены
docker compose up -d
docker logs -f hx-hermes
```

## Команды

| действие | команда |
|---|---|
| запуск | `docker compose up -d` |
| статус | `docker compose ps` |
| логи | `docker logs -f hx-hermes` |
| перезапуск | `docker compose restart hermes` |
| остановка | `docker compose down` |
| **после правки `.env`** | `docker compose up -d --force-recreate hermes` |

## Выбор модели и провайдера

Настроены два провайдера, ключи обоих лежат в `.env` одновременно — переключение
не требует их менять.

```bash
./switch-model.sh deepseek           # deepseek-v4-pro
./switch-model.sh kimi               # kimi-k3
./switch-model.sh kimi kimi-k2.6     # конкретная модель
./switch-model.sh status             # что активно сейчас и какие ключи видны
```

| провайдер | модели | ключ в `.env` |
|---|---|---|
| `deepseek` | `deepseek-v4-pro`, `deepseek-v4-flash` | `DEEPSEEK_API_KEY` |
| `kimi` | `kimi-k3` (1M контекст), `kimi-k2.7-code`, `kimi-k2.7-code-highspeed`, `kimi-k2.6` | `KIMI_API_KEY` |

Для Kimi обязателен `KIMI_BASE_URL=https://api.moonshot.ai/v1`: по умолчанию hermes
идёт на `api.moonshot.cn`, а китайский эндпоинт доступен не отовсюду.

Под капотом скрипт делает три `hermes config set` и `restart`. Вручную то же самое:

```yaml
# hermes-data/config.yaml — перекрывает переменные окружения
model:
  default: deepseek-v4-pro
  provider: deepseek
  base_url: https://api.deepseek.com/v1
```

Имя переменной с ключом должно соответствовать провайдеру: при `provider: deepseek`
читается `DEEPSEEK_API_KEY`, при `provider: kimi` — `KIMI_API_KEY`. Файл принадлежит
uid 10000, правится через `sudo`. `config.yaml` перечитывается при каждом старте,
так что достаточно `restart`.

Все модели обоих провайдеров — **reasoning**: часть токенов уходит на размышление
до ответа. При маленьком `max_tokens` ответ придёт пустым с `finish_reason: length`.

## Особенности конфигурации

Каждый пункт ниже — следствие конкретной поломки, а не стилистический выбор.

**`command: gateway run`**
Без аргументов контейнер запускает интерактивный TUI. TTY в фоне нет, stdin сразу
отдаёт EOF, агент считает это концом ввода и завершается с кодом 0 — и `restart`
поднимает его заново по кругу.

**`extra_hosts: api.telegram.org:149.154.167.220`**
DNS отдаёт для `api.telegram.org` адрес `149.154.166.110`, который с некоторых
хостов не отвечает (таймаут ~12 с). Живой адрес того же Bot API — `149.154.167.220`,
отвечает за 0.2 с. Без этой строки Telegram-адаптер уходит в перебор резервных
адресов через DNS-over-HTTPS и генерирует ~900 соединений в секунду.

Адрес прибит статически. Если он перестанет отвечать — подобрать другой из
диапазона `149.154.160.0/20` либо поднять прокси.

**`./hermes-data:/opt/data`**
В образе `HERMES_HOME=/opt/data`. Монтирование в `/root/.hermes` не работает:
агент туда ничего не пишет, и данные не переживают пересоздание контейнера.

**`mem_limit` / `pids_limit`**
Не оптимизация, а страховка. При сетевых сбоях агент уходит в шторм переподключений;
без лимитов это выедает память всей машины и приводит к global OOM — вплоть до
потери SSH. С лимитами процесс упирается в свой cgroup и умирает один.

**`restart: on-failure:3`**
Не `unless-stopped`: при циклическом падении docker сдаётся после трёх попыток,
а не крутит бесконечный цикл.

## WebDAV для Obsidian

Синхронизация хранилища Obsidian через плагин **Remotely Save**.

Настройки плагина (Settings → Remotely Save → Remote Service → WebDAV):

| поле | значение |
|---|---|
| Server Address | `https://5-8-9-221.sslip.io/webdav` |
| Username | из `WEBDAV_USERNAME` |
| Password | из `WEBDAV_PASSWORD` |
| Auth Type | Basic |
| Depth Header | `depth_1` |

### Карта путей

Один и тот же каталог виден по-разному в разных местах — это частый источник
путаницы, особенно если спрашивать про путь у самого агента:

| откуда смотрим | путь |
|---|---|
| файловая система сервера | `~/harness/webdav-data/me/` |
| контейнер `hx-webdav` | `/data/me/` |
| контейнер `hx-hermes` | `/opt/data/vault/` |
| по сети (WebDAV) | `https://5-8-9-221.sslip.io/webdav/me/` |
| Remotely Save (Server Address) | `https://5-8-9-221.sslip.io/webdav` (без `/me`) |

Хранилище примонтировано и в hermes — так агент может читать и править заметки,
а изменения подхватит Obsidian при следующей синхронизации. Монтируется внутрь
`/opt/data`, потому что у образа `HERMES_WRITE_SAFE_ROOT=/opt/data` и вне этого
пути агент писать отказывается. Чтобы дать доступ только на чтение — добавить
`:ro` к строке тома в `docker-compose.yml`.

Файлы лежат в `webdav-data/` рядом с compose — обычные каталоги, забрать можно
простым `scp` или `rsync`, без выгрузки через плагин.

### Про имя `5-8-9-221.sslip.io`

Домена у сервера нет, а сертификат на голый IP публичные CA не выдают.
`sslip.io` — публичный резолвер, который любое имя вида `1-2-3-4.sslip.io`
превращает в соответствующий адрес. Никаких DNS-записей заводить не нужно, но
имя настоящее, поэтому Let's Encrypt выдаёт на него обычный доверенный
сертификат — работает и в мобильном Obsidian.

Зависимость от стороннего сервиса тут только в резолвинге имени. Если `sslip.io`
станет недоступен — завести свою A-запись на `5.8.9.221` и поменять домен в
Caddyfile, всё остальное останется как есть.

### Аутентификация

WebDAV выведен в caddy **мимо** oauth2-proxy, которым закрыт остальной
`remote.unicort.ru`: Remotely Save умеет только basic auth и не проходит
OAuth-редиректы. Доступ защищён логином и паролем самого WebDAV поверх TLS.

## Ограничения

- **Только один экземпляр на бота.** Второй запущенный контейнер с тем же
  `TELEGRAM_BOT_TOKEN` будет отбирать слот long-polling, и оба получат
  `409 Conflict: terminated by other getUpdates request`.
- **Вспомогательный клиент.** В логах возможны предупреждения
  `Auxiliary Nous client unavailable`. Это сжатие контекста, суммаризация и
  заголовки сессий — на основной диалог не влияет, настраивается через `hermes auth`.

## Требования

Docker с плагином Compose v2. Проверялось на Docker 29 / Compose v2.40.
