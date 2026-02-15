# Hindsight Setup (macOS-first)

Локальная сборка Hindsight для macOS: API и модели запускаются в локальном Python,
а `docker-compose` используется только для PostgreSQL + pgvector.

![Docker Compose](https://img.shields.io/badge/docker-compose-2496ED?logo=docker&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgresql-16-4169E1?logo=postgresql&logoColor=white)
![pgvector](https://img.shields.io/badge/pgvector-enabled-2F855A)
![macOS](https://img.shields.io/badge/platform-macOS-111111?logo=apple&logoColor=white)

## Почему не full Docker

- На macOS в Docker Desktop нет нормального pass-through для CUDA/MPS под такой сценарий.
- Из-за этого embeddings/reranker внутри контейнера работают заметно хуже по производительности.
- Поэтому оптимальный путь: локальный Python-процесс (`hindsight-api`) + Postgres в Docker.

## Архитектура

```text
┌──────────────────────────────────────────┐
│ macOS host                               │
│  - hindsight-api (Python venv)           │
│  - local embeddings/reranker (MPS/CPU)   │
│  - UI via npx (optional)                 │
└───────────────────────┬──────────────────┘
                        │ localhost:5432
┌───────────────────────▼──────────────────┐
│ docker-compose                            │
│  - postgres (pgvector)                    │
└───────────────────────────────────────────┘
```

`docker-compose.yaml` в этом репозитории содержит только `postgres`.

## Быстрый старт

```bash
cp .env.example .env
# заполни минимум: HINDSIGHT_API_LLM_BASE_URL, HINDSIGHT_API_LLM_API_KEY

make install
make start
curl http://localhost:8888/health
```

После запуска:
- API: `http://localhost:8888`
- UI: `http://localhost:9999`

## Требования

- macOS (основной таргет этой сборки)
- Docker Desktop
- `uv`
- Node.js (только для UI, если нужен)

## Основные команды

- `make start` - поднять postgres, API и UI
- `make stop` - остановить API и UI
- `make stop-all` - остановить все, включая postgres
- `make status` - показать состояние сервисов
- `make logs` - смотреть логи API/UI
- `make health` - быстрый health-check API

## Конфигурация

Шаблон переменных: `.env.example`.

Важно:
- `.env` игнорируется git-ом
- в репозиторий коммитится только `.env.example`
- DB URL по умолчанию на localhost: `postgresql://hindsight:<db_password>@localhost:5432/hindsight_db`

## Troubleshooting

### API не стартует

- Проверь логи: `make logs`
- Проверь health: `make health`
- Убедись, что `.env` создан из `.env.example`

### Ошибка подключения к БД

- Убедись, что postgres поднят: `docker compose ps`
- Перезапусти postgres: `docker compose up -d postgres`

### UI не поднимается

- Установи Node.js (для `npx`)
- Или работай только с API, UI не обязателен

## Contribution / Security

- Contribution guide: `CONTRIBUTING.md`
- Security policy: `.github/SECURITY.md`
