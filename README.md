# Bench Frameworks: Go vs Python Performance Comparison

Монорепозиторий для сравнения производительности read-heavy API на **Go (chi + pgx)** и **Python (FastAPI + Pydantic v2 + asyncpg)** под нагрузкой.

Цель: честно сравнить latency/RPS/error-rate при одинаковых:
- схемах БД и данных,
- эндпоинтах и payload,
- CPU бюджете,
- общем бюджете DB connections,
- сценариях нагрузки (k6).

---

## Требования

### Обязательно
- Docker Desktop (Windows/macOS) или Docker Engine (Linux)
- Docker Compose

### Windows + WSL2
Docker должен быть доступен внутри WSL2:
1) Docker Desktop → Settings → Resources → WSL Integration
2) Включить интеграцию для нужного дистрибутива
3) Проверить в WSL:
   ```bash
   docker version
   docker compose version
   ````

Если видите “Cannot connect to the Docker daemon…”, почти всегда не включён WSL Integration.

### k6

Локально k6 не нужен — используется Docker-версия через `docker compose run`.

---

## Быстрый старт

1. Скопировать переменные окружения:

```bash
cp .env.example .env
```

2. Поднять всё (postgres + миграции + сид + оба API):

```bash
make up
```

3. Проверить health:

```bash
curl http://localhost:8080/healthz  # Go API
curl http://localhost:8081/healthz  # Python API
```

4. Запустить нагрузочные тесты (k6 в Docker):

```bash
make bench-go
make bench-py
```

5. Результаты:

```bash
ls -la loadtest/results
cat loadtest/results/go-*.json
cat loadtest/results/py-*.json
```

---

## Структура проекта

```text
bench-frameworks/
├── db/                          # База данных
│   ├── migrations/              # SQL миграции
│   └── seed/                    # Сид данных
├── go-api/                      # Go реализация API
│   ├── cmd/server/              # Entry point
│   └── internal/                # Внутренние пакеты
├── py-api/                      # Python реализация API
│   └── app/                     # Приложение FastAPI
├── loadtest/                    # Нагрузочное тестирование
│   ├── k6/                      # Сценарии k6
│   └── results/                 # Результаты тестов
└── scripts/                     # Вспомогательные скрипты
```

---

## Команды (Makefile)

* `make up` — postgres + миграции + сид + оба API
* `make up-go` — postgres + Go API
* `make up-py` — postgres + Python API
* `make down` — остановить все сервисы
* `make bench-go` — k6 тесты для Go (k6 через Docker)
* `make bench-py` — k6 тесты для Python (k6 через Docker)
* `make clean` — удалить volume БД (⚠️ удалит все данные)
* `make logs-go` — логи Go API
* `make logs-py` — логи Python API

---

## API Endpoints

Оба сервиса реализуют одинаковые эндпоинты.

### GET /healthz

```json
{"status": "ok"}
```

### GET /users/{id}

Response 200:

```json
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "email": "user1@example.com",
  "full_name": "User 1",
  "age": 25,
  "country_code": "US",
  "is_active": true,
  "created_at": "2026-01-31T08:00:00Z"
}
```

Response 404:

```json
{"error": "not_found"}
```

### GET /users

Query:

* `limit` (default: 50, max: 200)
* `offset` (default: 0)

Response 200:

```json
{
  "items": [],
  "limit": 50,
  "offset": 0,
  "total": 10000
}
```

---

## Нагрузочное тестирование (k6) — без локальной установки

k6 запускается в контейнере, поэтому:

* `localhost` внутри k6 — не ваш хост,
* target должен быть по имени сервиса compose-сети: `http://go-api:8080` или `http://py-api:8081`.

`make bench-go` / `make bench-py` уже используют правильные URL.

---

## Честность сравнения

Сравнение делается в двух режимах.

### Режим A: Single-instance efficiency (1 CPU, 1 процесс)

* CPU: 1 core на сервис
* Go: `GOMAXPROCS=1`
* Python: `UVICORN_WORKERS=1`
* DB connections total: 30

Запуск:

```bash
cp .env.single .env
docker compose -f docker-compose.yml -f docker-compose.single.yml --profile all up -d --build
make bench-go
make bench-py
```

### Режим B: Multi-core throughput (4 CPU)

* CPU: 4 cores на сервис
* Go: `GOMAXPROCS=4`
* Python: `UVICORN_WORKERS=4`
* DB connections total: 40
* Python per-worker pool: `DB_POOL_MAX_SIZE = 40 / 4 = 10`

Запуск:

```bash
cp .env.multi .env
docker compose -f docker-compose.yml -f docker-compose.multi.yml --profile all up -d --build
make bench-go
make bench-py
```

---

## Результаты нагрузочного тестирования (31 января 2026)

**Конфигурация:** 4 CPU cores, 40 DB connections total, PostgreSQL 16, 10,000 записей, memory limit 512MB на сервис.

### Go API

* net/http + chi v5
* pgxpool v5
* `GOMAXPROCS=4`
* DB conns: min 10 / max 40

### Python API

* FastAPI + Pydantic v2
* asyncpg
* `UVICORN_WORKERS=4`
* DB conns: 10 per worker × 4 = 40 total

---

### Тест 1: Light Load (10 VUs, 30s)

| Метрика          | Go API    | Python API | Разница         |
| ---------------- | --------- | ---------- | --------------- |
| Latency p50      | 1.2ms     | 2.5ms      | Go 2.1x быстрее |
| Latency p95      | 4.02ms    | 8.58ms     | Go 2.1x быстрее |
| Latency p99      | 4.83ms    | 10.4ms     | Go 2.2x быстрее |
| Throughput (RPS) | 106 req/s | 104 req/s  | ~равны (+2%)    |
| Error rate       | 0%        | 0%         | паритет         |
| Total requests   | 2,911     | 2,842      | -               |

Вывод: Go даёт ~2x меньшую latency при почти одинаковом RPS.

---

### Тест 2: Heavy Load (100 VUs, 2 min)

| Метрика          | Go API      | Python API  | Разница           |
| ---------------- | ----------- | ----------- | ----------------- |
| Latency p50      | 1.0ms       | 2.47ms      | Go 2.5x быстрее   |
| Latency p95      | 5.11ms      | 7.08ms      | Go 1.4x быстрее   |
| Latency p99      | 10.4ms      | 22.81ms     | Go 2.2x быстрее   |
| Latency max      | 88ms        | 1,980ms     | Go 22x стабильнее |
| Throughput (RPS) | 1,070 req/s | 1,054 req/s | ~равны (+1.5%)    |
| Error rate       | 0%          | 0%          | паритет           |
| Total requests   | 116,833     | 115,108     | -                 |

Вывод: throughput почти равный, но у Python сильные выбросы latency (max и p99).

---

### Общие выводы

* Latency: Go быстрее (примерно 1.4–2.5x по процентилям)
* Throughput (RPS): паритет (~1–2% разница)
* Стабильность: Go лучше (max latency 88ms vs 1980ms)
* Надежность: паритет (0% ошибок)

Файлы результатов:

* `loadtest/results/go-*.json`
* `loadtest/results/py-*.json`
* `loadtest/results/go-*.log`
* `loadtest/results/py-*.log`
* `loadtest/results/summary-multi.txt`

---

## Настройка параметров

Все параметры в `.env` (или `.env.single` / `.env.multi`).

### DB пулы

* Go:

  * `DB_MAX_CONNS`
  * `DB_MIN_CONNS`
* Python:

  * `DB_POOL_MAX_SIZE` (на один worker)
  * `DB_POOL_MIN_SIZE` (на один worker)
* Python workers:

  * `UVICORN_WORKERS`

---

## Troubleshooting

### Go: checksum mismatch / go.sum

```bash
cd go-api
go clean -modcache
go mod tidy
go mod verify
```

### Docker недоступен в WSL2

Docker Desktop → Settings → Resources → WSL Integration → включить дистрибутив.
Проверка:

```bash
docker version
docker compose version
```

### k6 не установлен / apt/brew не работает

k6 ставить не нужно:

```bash
make bench-go
make bench-py
```

### Нечестные результаты (CPU/DB connections)

Проверьте:

* одинаковые CPU лимиты для go-api и py-api
* одинаковый TOTAL_DB_CONNS
* Python pool делится на воркеры: `DB_POOL_MAX_SIZE = TOTAL_DB_CONNS / UVICORN_WORKERS`

---

## Лицензия

MIT
