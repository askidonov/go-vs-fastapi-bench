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
- **Docker Desktop** (Windows/macOS) или Docker Engine (Linux)
- **Docker Compose** (в составе Docker Desktop или отдельно)

### Windows + WSL2 (важно)
Если вы запускаете из WSL2, Docker должен быть доступен **внутри** дистрибутива:
1) Docker Desktop → **Settings** → **Resources** → **WSL Integration**
2) Включить интеграцию для нужного дистрибутива (Ubuntu/Debian и т.д.)
3) Проверить в WSL:
   ```bash
   docker version
   docker compose version
   ```


Если видите ошибку вида “Cannot connect to the Docker daemon…”, это почти всегда не включён WSL Integration.

### k6

Локально устанавливать k6 **не требуется** — репозиторий использует **Docker-версию k6** (через `docker compose run`).
Это избавляет от проблем установки через `apt` и сетевых таймаутов.

---

## Быстрый старт (самый простой путь)

1. **Скопировать переменные окружения:**

```bash
cp .env.example .env
```

2. **Поднять всё (postgres + миграции + сид + оба API):**

```bash
make up
```

3. **Проверить health:**

```bash
curl http://localhost:8080/healthz  # Go API
curl http://localhost:8081/healthz  # Python API
```

4. **Запустить нагрузочные тесты (k6 в Docker):**

```bash
make bench-go
make bench-py
```

5. **Посмотреть результаты:**

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

* `make up` — поднять postgres + миграции + сид + оба API
* `make up-go` — поднять postgres + Go API
* `make up-py` — поднять postgres + Python API
* `make down` — остановить все сервисы
* `make bench-go` — запустить k6 тесты для Go API (k6 через Docker)
* `make bench-py` — запустить k6 тесты для Python API (k6 через Docker)
* `make clean` — удалить volume БД (⚠️ удалит все данные)
* `make logs-go` — показать логи Go API
* `make logs-py` — показать логи Python API

---

## API Endpoints

Оба сервиса реализуют одинаковые эндпоинты.

### GET /healthz

Проверка здоровья сервиса.

**Response:**

```json
{"status": "ok"}
```

### GET /users/{id}

Получить пользователя по UUID.

**Response 200:**

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

**Response 404:**

```json
{"error": "not_found"}
```

### GET /users

Получить список пользователей с пагинацией.

**Query параметры:**

* `limit` (int, default: 50, max: 200)
* `offset` (int, default: 0)

**Response 200:**

```json
{
  "items": [/* массив User объектов */],
  "limit": 50,
  "offset": 0,
  "total": 10000
}
```

---

## Нагрузочное тестирование (k6) — без локальной установки

### Почему k6 запускается в Docker

* не надо ставить k6 через `apt`/`brew`,
* меньше проблем с сетью/ключами/репозиториями,
* одинаковый способ запуска на любой ОС.

### Важно про сеть

k6 запускается **в контейнере**, поэтому:

* `localhost` внутри k6 контейнера — это **не ваш хост**,
* сценарии должны ходить по имени сервиса compose-сети: `http://go-api:8080` или `http://py-api:8081`.

Команды `make bench-go` / `make bench-py` уже настроены правильно.

---

## Честность сравнения — как запускать правильно

Чтобы не получить “нечестные” результаты (например, Go использует все CPU, а Python ограничен), сравнение делается в двух режимах.

### Режим A: Single-instance efficiency (1 CPU, 1 процесс)

Цель: сравнить **один процесс** на **одном ядре**.

* CPU: **1 core** для каждого сервиса
* Go: `GOMAXPROCS=1`
* Python: `UVICORN_WORKERS=1`
* Общий бюджет DB connections: фиксированный (например **30 total**)

Запуск (если в репо есть override-файл):

```bash
cp .env.single .env
docker compose -f docker-compose.yml -f docker-compose.single.yml --profile all up -d --build
make bench-go
make bench-py
```

### Режим B: Multi-core throughput (4 CPU, масштабирование)

Цель: сравнить throughput при одинаковом CPU бюджете.

* CPU: **4 cores** для каждого сервиса
* Go: `GOMAXPROCS=4`
* Python: `UVICORN_WORKERS=4`
* Общий бюджет DB connections: фиксированный (например **40 total**)

Ключевой момент: **Python pool на воркер** должен делиться:

* TOTAL_DB_CONNS = 40
* workers = 4
* `DB_POOL_MAX_SIZE = 10` (10 × 4 = 40 total)

Запуск:

```bash
cp .env.multi .env
docker compose -f docker-compose.yml -f docker-compose.multi.yml --profile all up -d --build
make bench-go
make bench-py
```

### Почему это важно

* `UVICORN_WORKERS` = N → **N процессов**, и каждый создаёт свой пул БД.
* Если не делить пул, Python может случайно открыть в N раз больше соединений к Postgres, и сравнение станет про DB connections, а не про runtime/framework.

---

## Настройка параметров

Все параметры находятся в `.env` (или `.env.single` / `.env.multi`).

### База данных / пулы

* Go:

  * `DB_MAX_CONNS` — max соединений для Go API
  * `DB_MIN_CONNS` — min соединений для Go API
* Python:

  * `DB_POOL_MAX_SIZE` — max размер пула на **один** worker
  * `DB_POOL_MIN_SIZE` — min размер пула на **один** worker
* Python workers:

  * `UVICORN_WORKERS` — число процессов uvicorn

### Параметры k6

Редактируются в `loadtest/k6/*.js`:

* профили нагрузки (VUs, duration, ramp)

---

## Интерпретация результатов

После `make bench-go` / `make bench-py` смотрите:

1. **http_req_duration** — latency:

   * p(50), p(95), p(99)
2. **http_req_failed** — % ошибок (идеально 0%)
3. **iterations** — сколько итераций выполнено

Пример:

```text
http_req_duration: avg=5ms med=4ms p(95)=12ms p(99)=20ms max=50ms
http_req_failed:   0.00%
iterations:        50000
```

---

## Troubleshooting (частые проблемы и решения)

### 1) Go: ошибка контрольных сумм / go.sum (checksum mismatch)

Иногда модкеш содержит неконсистентные версии или `go.sum`/`go.mod` не синхронизированы.

Решение:

```bash
cd go-api
go clean -modcache
go mod tidy
go mod verify
```

⚠️ Удалять `go.sum` можно как аварийный вариант, но предпочтительнее команды выше.

### 2) Docker не доступен в WSL2

Симптом: `Cannot connect to the Docker daemon...` из WSL.

Решение:
Docker Desktop → Settings → Resources → WSL Integration → включить ваш дистрибутив.
Проверка:

```bash
docker version
docker compose version
```

### 3) k6 не установлен / apt/brew не работает

Ничего ставить не нужно — используйте:

```bash
make bench-go
make bench-py
```

### 4) “Нечестные” результаты (разные CPU / разные DB connections)

Проверьте:

* одинаковые CPU лимиты для go-api и py-api,
* одинаковый TOTAL_DB_CONNS,
* Python pool делится на число воркеров:

  * `DB_POOL_MAX_SIZE = TOTAL_DB_CONNS / UVICORN_WORKERS`

---

## Лицензия

MIT
