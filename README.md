# Hindsight — Мультиязычная конфигурация (RU/EN)

Настройка [Hindsight](https://hindsight.vectorize.io/) для работы с русским и английским языками.

![Docker Compose](https://img.shields.io/badge/docker-compose-2496ED?logo=docker&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgresql-16-4169E1?logo=postgresql&logoColor=white)
![pgvector](https://img.shields.io/badge/pgvector-enabled-2F855A)
![MCP](https://img.shields.io/badge/MCP-enabled-0A66C2)

## Быстрый старт

```bash
cp .env.example .env
# отредактируй .env (LLM provider, base URL, API key)

make install
make start
curl http://localhost:8888/health
```

- Contribution guide: `CONTRIBUTING.md`
- Security policy: `.github/SECURITY.md`

## Оглавление

- [Быстрый старт](#быстрый-старт)
- [Обзор архитектуры](#обзор-архитектуры)
- [Рекомендуемые модели](#рекомендуемые-модели)
- [Квантование моделей](#квантование-моделей)
- [Варианты развёртывания](#варианты-развёртывания)
- [Конфигурация](#конфигурация)
- [Запуск](#запуск)
- [Troubleshooting](#troubleshooting)

---

## Обзор архитектуры

Hindsight использует три типа моделей:

| Компонент | Назначение | Когда используется |
|-----------|------------|-------------------|
| **LLM** | Извлечение фактов, генерация ответов | `retain`, `reflect` операции |
| **Embeddings** | Преобразование текста в векторы | Семантический поиск |
| **Reranker** | Переранжирование результатов | Улучшение релевантности |

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    LLM      │     │  Embeddings │     │  Reranker   │
│(Cloud/Groq) │     │  (BGE-M3)   │     │(BGE-reranker)│
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┴───────────────────┘
                           │
                    ┌──────┴──────┐
                    │  Hindsight  │
                    │    API      │
                    └──────┬──────┘
                           │
                    ┌──────┴──────┐
                    │  PostgreSQL │
                    │  + pgvector │
                    └─────────────┘
```

---

## Рекомендуемые модели

### Embeddings (мультиязычные)

| Модель | Параметры | Размерность | RAM (FP16) | Качество RU | Примечание |
|--------|-----------|-------------|------------|-------------|------------|
| **`BAAI/bge-m3`** | 568M | 1024 | ~1.2GB | ⭐⭐⭐⭐⭐ | **Рекомендуется** — лидер MIRACL |
| `intfloat/multilingual-e5-large` | 560M | 1024 | ~1.1GB | ⭐⭐⭐⭐ | Хорошая альтернатива |
| `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` | 118M | 384 | ~250MB | ⭐⭐⭐ | Лёгкая модель |

### Reranker (мультиязычные)

| Модель | Параметры | RAM (FP16) | Качество RU | Примечание |
|--------|-----------|------------|-------------|------------|
| **`BAAI/bge-reranker-v2-m3`** | 568M | ~1.2GB | ⭐⭐⭐⭐⭐ | **Рекомендуется** |
| `cross-encoder/mmarco-mMiniLMv2-L12-H384-v1` | 118M | ~250MB | ⭐⭐⭐ | Лёгкая альтернатива |
| `jinaai/jina-reranker-v2-base-multilingual` | 278M | ~560MB | ⭐⭐⭐⭐ | Хороший баланс |

### LLM (облачные провайдеры)

Рекомендуемые провайдеры с бесплатными лимитами:

| Провайдер | Модель | Бесплатный лимит | Качество RU |
|-----------|--------|------------------|-------------|
| **Кастомный endpoint** | `glm4.7` | Зависит от провайдера | ⭐⭐⭐⭐⭐ |
| **Groq** | `openai/gpt-oss-120b` | Быстрый, лимиты по RPM | ⭐⭐⭐⭐ |
| **Cerebras** | `gpt-oss-120b` | 1M токенов/день | ⭐⭐⭐⭐ |
| Anthropic | `claude-sonnet-4` | Платный | ⭐⭐⭐⭐⭐ |
| OpenAI | `gpt-4o-mini` | Платный | ⭐⭐⭐⭐ |

> ⚠️ **Важно:** Hindsight требует модели с поддержкой минимум 65,000 output tokens для надёжного извлечения фактов.

---

## Квантование моделей

### BGE-M3 (Embeddings)

#### Для Hindsight local provider (SentenceTransformers)

Hindsight автоматически использует FP16 для оптимизации памяти. Дополнительная настройка не требуется.

```bash
# Hindsight сам скачает модель при первом запуске
HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL=BAAI/bge-m3
```

#### GGUF квантованные версии (для Ollama/llama.cpp)

| Квантование | Размер | RAM | Качество | Рекомендация |
|-------------|--------|-----|----------|--------------|
| `F16` | 1.16 GB | ~2.5GB | 100% | Максимальное качество |
| **`Q8_0`** | 635 MB | ~1.3GB | ~99% | **Рекомендуется** |
| `Q6_K` | 499 MB | ~1GB | ~98% | Хороший баланс |
| **`Q4_K_M`** | 438 MB | ~900MB | ~95% | **Баланс размер/качество** |
| `Q4_K_S` | 424 MB | ~850MB | ~94% | Минимальный размер |
| `Q2_K` | 366 MB | ~750MB | ~85% | Не рекомендуется |

**Источники GGUF:**
- [lm-kit/bge-m3-gguf](https://huggingface.co/lm-kit/bge-m3-gguf) — все квантования
- [gpustack/bge-m3-GGUF](https://huggingface.co/gpustack/bge-m3-GGUF) — все квантования
- [ggml-org/bge-m3-Q8_0-GGUF](https://huggingface.co/ggml-org/bge-m3-Q8_0-GGUF) — только Q8

**Ollama:**
```bash
# Q4_K_M (рекомендуется для ограниченной памяти)
ollama pull qllama/bge-m3:q4_k_m

# Или стандартный
ollama pull bge-m3
```

### BGE-Reranker-v2-m3 (Reranker)

#### Для Hindsight local provider

```bash
# FP16 автоматически
HINDSIGHT_API_RERANKER_LOCAL_MODEL=BAAI/bge-reranker-v2-m3
```

#### GGUF квантованные версии

| Квантование | Размер | RAM | Источник |
|-------------|--------|-----|----------|
| **`Q8_0`** | ~635 MB | ~1.3GB | [gpustack/bge-reranker-v2-m3-GGUF](https://huggingface.co/gpustack/bge-reranker-v2-m3-GGUF) |
| `Q8_0` | ~635 MB | ~1.3GB | [klnstpr/bge-reranker-v2-m3-Q8_0-GGUF](https://huggingface.co/klnstpr/bge-reranker-v2-m3-Q8_0-GGUF) |

> ⚠️ Q4 квантование для reranker моделей не рекомендуется — значительно снижает качество ранжирования.

---

## Варианты развёртывания

### Вариант 1: Облачный LLM + Local Embeddings (рекомендуется)

Hindsight использует встроенный SentenceTransformers для embeddings/reranker, а LLM — через облачный API.

**Плюсы:** Бесплатные LLM лимиты, простота настройки
**Минусы:** Зависимость от интернета для LLM

```
┌─────────────────────────────────┐
│         Hindsight               │
│  ┌───────────┐ ┌─────────────┐  │
│  │ Embeddings│ │  Reranker   │  │
│  │ (BGE-M3)  │ │(BGE-reranker)│ │
│  └───────────┘ └─────────────┘  │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│   Cloud LLM (Groq/Cerebras/    │
│   Custom endpoint)              │
└─────────────────────────────────┘
```

### Вариант 2: Ollama для embeddings

Используй Ollama для эмбедингов, Hindsight для reranker.

**Плюсы:** Меньше RAM для Hindsight, GGUF квантование
**Минусы:** Дополнительный сервис

```bash
# Запустить Ollama
ollama serve

# Скачать модель
ollama pull bge-m3
```

```bash
# .env
HINDSIGHT_API_EMBEDDINGS_PROVIDER=ollama
HINDSIGHT_API_EMBEDDINGS_OLLAMA_BASE_URL=http://host.docker.internal:11434
HINDSIGHT_API_EMBEDDINGS_OLLAMA_MODEL=bge-m3
```

### Вариант 3: TEI (Text Embeddings Inference)

Для production с GPU ускорением.

```yaml
# docker-compose.yaml (добавить сервис)
tei:
  image: ghcr.io/huggingface/text-embeddings-inference:cpu-1.5
  command: --model-id BAAI/bge-m3
  ports:
    - "8080:80"
```

```bash
# .env
HINDSIGHT_API_EMBEDDINGS_PROVIDER=tei
HINDSIGHT_API_EMBEDDINGS_TEI_URL=http://tei:80
```

---

## Конфигурация

### Файл `.env`

```bash
# ===========================================
# HINDSIGHT — Мультиязычная конфигурация (RU/EN)
# ===========================================

# --- LLM Settings ---
# Текущий: кастомный endpoint (OpenAI-compatible)
HINDSIGHT_API_LLM_PROVIDER=anthropic
HINDSIGHT_API_LLM_BASE_URL=https://ccr.prodentcrm.ru
HINDSIGHT_API_LLM_API_KEY=your_api_key_here
HINDSIGHT_API_LLM_MODEL=glm4.7

# --- Альтернативные LLM провайдеры ---
#
# Groq (бесплатно, быстрый):
# HINDSIGHT_API_LLM_PROVIDER=groq
# HINDSIGHT_API_LLM_API_KEY=gsk_your_groq_key
# HINDSIGHT_API_LLM_MODEL=openai/gpt-oss-120b
#
# Cerebras (бесплатно, 1M токенов/день):
# HINDSIGHT_API_LLM_PROVIDER=openai
# HINDSIGHT_API_LLM_BASE_URL=https://api.cerebras.ai/v1
# HINDSIGHT_API_LLM_API_KEY=your_cerebras_key
# HINDSIGHT_API_LLM_MODEL=gpt-oss-120b

HINDSIGHT_API_LLM_MAX_CONCURRENT=8
HINDSIGHT_API_LLM_TIMEOUT=180

# --- Embeddings (мультиязычные) ---
HINDSIGHT_API_EMBEDDINGS_PROVIDER=local
HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL=BAAI/bge-m3

# --- Reranker (мультиязычный) ---
HINDSIGHT_API_RERANKER_PROVIDER=local
HINDSIGHT_API_RERANKER_LOCAL_MODEL=BAAI/bge-reranker-v2-m3
HINDSIGHT_API_RERANKER_LOCAL_MAX_CONCURRENT=4

# --- Database ---
HINDSIGHT_API_DATABASE_URL=postgresql://hindsight:secure_password@postgres:5432/hindsight_db
HINDSIGHT_API_STORE_TYPE=postgres
HINDSIGHT_API_DB_POOL_MIN_SIZE=5
HINDSIGHT_API_DB_POOL_MAX_SIZE=50

# --- Retrieval ---
HINDSIGHT_API_GRAPH_RETRIEVER=link_expansion
HINDSIGHT_API_RERANKER_MAX_CANDIDATES=300

# --- Pipeline ---
HINDSIGHT_API_RETAIN_MAX_COMPLETION_TOKENS=64000
HINDSIGHT_API_RETAIN_CHUNK_SIZE=3000
HINDSIGHT_API_RETAIN_EXTRACTION_MODE=concise

# --- Server ---
HINDSIGHT_API_LOG_LEVEL=info
HINDSIGHT_API_MCP_ENABLED=true
```

### Файл `docker-compose.yaml`

```yaml
services:
  hindsight:
    image: ghcr.io/vectorize-io/hindsight:latest
    container_name: hindsight
    restart: unless-stopped
    ports:
      - "8888:8888" # API & MCP
      - "9090:9999" # UI
    environment:
      # LLM (из .env)
      - HINDSIGHT_API_LLM_PROVIDER=${HINDSIGHT_API_LLM_PROVIDER}
      - HINDSIGHT_API_LLM_BASE_URL=${HINDSIGHT_API_LLM_BASE_URL}
      - HINDSIGHT_API_LLM_API_KEY=${HINDSIGHT_API_LLM_API_KEY}
      - HINDSIGHT_API_LLM_MODEL=${HINDSIGHT_API_LLM_MODEL}
      - HINDSIGHT_API_LLM_MAX_CONCURRENT=${HINDSIGHT_API_LLM_MAX_CONCURRENT:-8}
      - HINDSIGHT_API_LLM_TIMEOUT=${HINDSIGHT_API_LLM_TIMEOUT:-180}

      # Embeddings (мультиязычные)
      - HINDSIGHT_API_EMBEDDINGS_PROVIDER=local
      - HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL=BAAI/bge-m3

      # Reranker (мультиязычный)
      - HINDSIGHT_API_RERANKER_PROVIDER=local
      - HINDSIGHT_API_RERANKER_LOCAL_MODEL=BAAI/bge-reranker-v2-m3
      - HINDSIGHT_API_RERANKER_LOCAL_MAX_CONCURRENT=4

      # Database
      - HINDSIGHT_API_DATABASE_URL=postgresql://hindsight:secure_password@postgres:5432/hindsight_db
      - HINDSIGHT_API_STORE_TYPE=postgres
      - HINDSIGHT_API_DB_POOL_MIN_SIZE=5
      - HINDSIGHT_API_DB_POOL_MAX_SIZE=50

      # Retrieval & Pipeline
      - HINDSIGHT_API_GRAPH_RETRIEVER=link_expansion
      - HINDSIGHT_API_RERANKER_MAX_CANDIDATES=300
      - HINDSIGHT_API_RETAIN_MAX_COMPLETION_TOKENS=64000
      - HINDSIGHT_API_RETAIN_CHUNK_SIZE=3000

      # Server
      - HINDSIGHT_API_LOG_LEVEL=info
      - HINDSIGHT_API_MCP_ENABLED=true
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - hindsight-net
    deploy:
      resources:
        limits:
          memory: 8G

  postgres:
    image: pgvector/pgvector:pg16
    container_name: hindsight-postgres
    restart: always
    environment:
      POSTGRES_USER: hindsight
      POSTGRES_PASSWORD: secure_password
      POSTGRES_DB: hindsight_db
    command: >
      postgres -c "shared_preload_libraries=vector"
    shm_size: 1g
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init-db.sql:/docker-entrypoint-initdb.d/init.sql
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U hindsight -d hindsight_db"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - hindsight-net

volumes:
  postgres-data:

networks:
  hindsight-net:
    driver: bridge
```

### Альтернативная конфигурация (минимум RAM)

Если памяти мало (~4GB), используй лёгкие модели:

```bash
# .env (лёгкая версия)
HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL=sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2
HINDSIGHT_API_RERANKER_LOCAL_MODEL=cross-encoder/mmarco-mMiniLMv2-L12-H384-v1
```

---

## Запуск

### 1. Подготовка

```bash
# Создать init-db.sql если не существует
cat > init-db.sql << 'EOF'
CREATE EXTENSION IF NOT EXISTS vector;
EOF
```

### 2. Настройка LLM провайдера

Отредактируй `.env` файл и укажи свой LLM провайдер:

**Кастомный endpoint:**
```bash
HINDSIGHT_API_LLM_PROVIDER=anthropic
HINDSIGHT_API_LLM_BASE_URL=https://your-endpoint.com
HINDSIGHT_API_LLM_API_KEY=your_api_key
HINDSIGHT_API_LLM_MODEL=glm4.7
```

**Groq:**
```bash
HINDSIGHT_API_LLM_PROVIDER=groq
HINDSIGHT_API_LLM_API_KEY=gsk_your_key
HINDSIGHT_API_LLM_MODEL=openai/gpt-oss-120b
```

**Cerebras:**
```bash
HINDSIGHT_API_LLM_PROVIDER=openai
HINDSIGHT_API_LLM_BASE_URL=https://api.cerebras.ai/v1
HINDSIGHT_API_LLM_API_KEY=your_key
HINDSIGHT_API_LLM_MODEL=gpt-oss-120b
```

### 3. Запуск Hindsight

```bash
docker-compose up -d
```

### 4. Проверка

```bash
# Логи
docker-compose logs -f hindsight

# Статус
curl http://localhost:8888/health
```

**Первый запуск:** модели (~3GB) скачиваются автоматически. Это займёт время.

---

## Troubleshooting

### Ошибка "type vector does not exist"

База данных не инициализирована с pgvector:

```bash
docker-compose down -v  # Удалит данные!
docker-compose up -d
```

### Out of Memory

Используй лёгкие модели или увеличь лимит памяти:

```yaml
deploy:
  resources:
    limits:
      memory: 12G
```

### LLM провайдер не отвечает

1. Проверь доступность endpoint: `curl https://your-endpoint.com/v1/models`
2. Проверь правильность API ключа
3. Для Groq проверь лимиты: https://console.groq.com/

### Модели не скачиваются

Проверь интернет-соединение и доступ к HuggingFace:

```bash
docker exec hindsight curl -I https://huggingface.co
```

### Низкое качество на русском

1. Убедись что используешь мультиязычные модели (BGE-M3, не bge-small-en)
2. Проверь что LLM поддерживает русский (Qwen, не чисто английские модели)

---

## Требования к ресурсам

| Конфигурация | RAM | Примечание |
|--------------|-----|------------|
| Минимальная | 6GB | Лёгкие модели, медленный LLM |
| Рекомендуемая | 12GB | BGE-M3 + BGE-reranker + 7B LLM |
| Оптимальная | 16GB+ | Полные модели + 14B LLM |

---

## Ссылки

- [Hindsight Documentation](https://hindsight.vectorize.io/developer/models)
- [BGE-M3 на HuggingFace](https://huggingface.co/BAAI/bge-m3)
- [BGE-Reranker-v2-m3](https://huggingface.co/BAAI/bge-reranker-v2-m3)
- [ruMTEB Benchmark](https://arxiv.org/html/2408.12503v1)
- [MMTEB Multilingual Benchmark](https://arxiv.org/abs/2502.13595)
- [LM Studio Embeddings](https://lmstudio.ai/docs/text-embeddings)
