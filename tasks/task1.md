Ниже — готовое **ТЗ/спека для Copilot Agent**: один монорепозиторий, две реализации одного и того же API (read-heavy), общий Postgres в контейнере, сид на несколько тысяч записей, и нагрузочное тестирование через **k6** (удобно параметризовать base URL). k6 актуален и активно развивается (в документации “latest” ветка v1.5.x). ([Grafana Labs][1])

---

## 1) Цель эксперимента

Сравнить **производительность под нагрузкой** (RPS, latency p50/p95/p99, error rate) для одинакового сценария:

* **Python:** FastAPI + Pydantic v2 (актуальная ветка 2.12.x в документации). ([Pydantic][2])
  FastAPI уже ориентируется на Python 3.9+ (в release notes отмечено обновление внутреннего синтаксиса и дроп 3.8). ([FastAPI][3])
* **Go:** net/http + chi router (ветка v5.x). ([GitHub][4])

**Фокус:** read-only запросы к PostgreSQL (SELECT по юзерам) + сериализация ответа.

---

## 2) Общие принципы “честного” сравнения

1. **Одинаковая схема БД и одинаковые данные** для обоих сервисов.
2. **Одинаковые эндпоинты и одинаковые JSON-ответы** (одинаковые поля, типы, порядок полей не важен).
3. **Логи/трейсы по умолчанию выключены** (иначе они “съедят” часть производительности).
4. Нагрузочные тесты гоняются **одинаковыми сценариями k6**, меняется только `BASE_URL`.
5. Отдельно прогоняем режимы:

   * *Python 1 worker* (чистая async-конкурентность)
   * *Python N workers* (масштабирование воркерами)
   * *Go* (по умолчанию)

---

## 3) Репозиторий (monorepo) — структура

```
bench-frameworks/
  README.md
  docker-compose.yml
  .env.example

  db/
    migrations/
      001_init.sql
    seed/
      001_seed_users.sql

  go-api/
    Dockerfile
    go.mod
    cmd/server/main.go
    internal/
      http/
      db/
      model/
      config/

  py-api/
    Dockerfile
    pyproject.toml  (или requirements.txt)
    app/
      main.py
      api.py
      db.py
      models.py
      schemas.py
      config.py

  loadtest/
    k6/
      read_user.js
      list_users.js
      mixed.js
    results/  (сюда складывать выходные json/text)

  scripts/
    run_k6.sh
    wait_for.sh

  Makefile
```

---

## 4) База данных

### 4.1 Схема `users`

**Таблица:** `users`

Поля (пример, можно 6–10 штук, но одинаково в обоих сервисах):

* `id UUID PK`
* `email TEXT UNIQUE NOT NULL`
* `full_name TEXT NOT NULL`
* `age INT NOT NULL`
* `country_code CHAR(2) NOT NULL`
* `is_active BOOL NOT NULL`
* `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`

Индексы:

* PK по `id`
* UNIQUE по `email`
* (опционально) индекс по `created_at`

### 4.2 Миграция

`db/migrations/001_init.sql`:

* `CREATE EXTENSION IF NOT EXISTS pgcrypto;` (для `gen_random_uuid()`)
* `CREATE TABLE users (...)`
* индексы

### 4.3 Сид

`db/seed/001_seed_users.sql`:

* вставить **например 10_000** записей через `generate_series`.
* генерировать email `user{n}@example.com`, имя, возраст, страну, `is_active`.

Важно: сид должен выполняться один раз на “чистой” базе.

---

## 5) API-контракт (одинаковый в Go и Python)

### 5.1 Endpoints

1. `GET /healthz`
   **200 OK**: `{"status":"ok"}`

2. `GET /users/{id}`
   **200 OK**: объект `User`
   **404**: `{"error":"not_found"}`

3. `GET /users`
   Параметры: `limit` (default 50, max 200), `offset` (default 0)
   **200 OK**:

```json
{
  "items": [User, ...],
  "limit": 50,
  "offset": 0,
  "total": 10000
}
```

4. (опционально, полезно для теста индексного поиска) `GET /users/by-email?email=...`

### 5.2 DTO User (ответ)

```json
{
  "id": "uuid",
  "email": "user1@example.com",
  "full_name": "User 1",
  "age": 25,
  "country_code": "US",
  "is_active": true,
  "created_at": "2026-01-31T08:00:00Z"
}
```

---

## 6) Реализация сервиса на Go (chi)

Требования:

* Go версия: ориентироваться на актуальную стабильную линейку (на сайте Go релизы 1.25.x упоминаются как актуальные). ([Go][5])
* Router: `github.com/go-chi/chi/v5`. ([GitHub][6])
* Доступ к БД: `pgx/v5` + `pgxpool`.
* Сериализация: стандартный `encoding/json` (без “ускорителей”, чтобы не усложнять сравнение).
* Таймауты сервера: ReadHeader/Read/Write/Idle.
* Пулы: настраиваемые env-переменными:

  * `DB_MAX_CONNS`, `DB_MIN_CONNS`
* SQL:

  * `GetUserByID`: `SELECT ... FROM users WHERE id=$1`
  * `ListUsers`: `SELECT ... ORDER BY created_at DESC LIMIT $1 OFFSET $2`
  * `Total`: `SELECT count(*) FROM users`

---

## 7) Реализация сервиса на Python (FastAPI + Pydantic v2)

Требования:

* FastAPI + Pydantic v2 (актуальная документация Pydantic v2.12.x). ([Pydantic][2])
  FastAPI по release notes ориентируется на Python 3.9+. ([FastAPI][3])
* Запуск через `uvicorn`.
* Доступ к БД: **asyncpg** (чтобы не смешивать сравнение с ORM-оверходом).
  *(Опционально вторым режимом можно добавить SQLAlchemy async, но это уже “вторая серия”.)*
* Пул соединений: env

  * `DB_POOL_MIN_SIZE`, `DB_POOL_MAX_SIZE`
* Pydantic-схемы (v2) для response models.
* Включить “production” настройки:

  * выключить access log по умолчанию
  * `PYTHONUNBUFFERED=1`
  * конфиг воркеров через `UVICORN_WORKERS` (по умолчанию 1)

---

## 8) Docker Compose

`docker-compose.yml` должен поднимать:

* `postgres` (например `postgres:16-alpine`)
* `db-migrate` (одноразовый сервис, применяет миграции)
* `db-seed` (одноразовый сервис, сидит данные)
* `go-api`
* `py-api`

Рекомендация: использовать `profiles`, чтобы можно было поднять только один сервис и Postgres.

Переменные через `.env`:

* `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
* `DB_HOST=postgres`, `DB_PORT=5432`
* `GO_PORT=8080`, `PY_PORT=8081`

---

## 9) Нагрузочное тестирование (k6)

### 9.1 Почему k6

* сценарии кодом (JS),
* легко переключать target через env,
* нормальные метрики latency/percentiles,
* удобно сохранять результаты. ([k6.io][7])

### 9.2 Сценарии

`loadtest/k6/read_user.js`:

* в `setup()` дернуть `GET /users?limit=200&offset=0` несколько раз, собрать список `id` (или сделать отдельный эндпоинт `GET /users/ids?limit=...` — но лучше не добавлять лишнего).
* в тесте: случайно выбирать id и дергать `GET /users/{id}`

`loadtest/k6/list_users.js`:

* дергать `GET /users?limit=50&offset=rand(0..N)`

`loadtest/k6/mixed.js`:

* 70% `GET /users/{id}`
* 30% `GET /users?limit=50&offset=...`

### 9.3 Режимы нагрузки (минимум 3)

1. **smoke**: 10 VUs, 30s
2. **steady**: 100 VUs, 2–5 min
3. **ramp**: 0→200 VUs за 2 min, держать 2 min, спад

Результаты сохранять:

* `--summary-export loadtest/results/<name>.json`
* плюс консольный summary.

### 9.4 Запуск

Скрипт `scripts/run_k6.sh`:

* принимает `BASE_URL`
* имя сценария
* сохраняет результаты в `loadtest/results/`

Пример (как должно получиться):

* `make bench-go` → гоняет k6 на `http://localhost:8080`
* `make bench-py` → гоняет k6 на `http://localhost:8081`

---

## 10) Makefile (обязательные цели)

* `make up` — поднять postgres + миграции + сид + оба сервиса
* `make up-go` — postgres + миграции + сид + go-api
* `make up-py` — postgres + миграции + сид + py-api
* `make down` — остановить
* `make bench-go` — прогнать все k6 сценарии по Go
* `make bench-py` — прогнать все k6 сценарии по Python
* `make clean` — удалить volume БД (осторожно)

---

## 11) README.md — что должно быть описано

* требования (Docker, Docker Compose, k6 локально **или** через контейнер)
* быстрый старт (3–5 команд)
* как менять параметры (VUs, duration, workers, pool sizes)
* как интерпретировать результаты (p95/p99, error rate)
* рекомендации “как не сломать честность сравнения” (не включать дебаг-логирование, не менять payload без синхронизации, фиксировать железо)

---

## 12) Acceptance Criteria (критерии готовности)

1. `docker compose up` поднимает Postgres, применяет миграции, сидит данные, поднимает оба API.
2. Оба API отвечают одинаковыми JSON на одинаковые запросы.
3. k6 сценарии работают и для Go, и для Python (переключение только через `BASE_URL`).
4. `make bench-go` и `make bench-py` кладут результаты в `loadtest/results/` (json).
5. В README есть воспроизводимая инструкция запуска и список параметров тюнинга.

---

# Готовый “Prompt для Copilot Agent” (можно вставить как есть)

Скопируй и отдай агенту:

> Ты — coding agent. Создай монорепозиторий `bench-frameworks` для сравнения производительности под нагрузкой:
> **(1)** Go сервис на `net/http + chi v5 + pgxpool`, **(2)** Python сервис на `FastAPI + Pydantic v2 + asyncpg`.
> Оба сервиса должны использовать **одну и ту же** PostgreSQL в Docker, **одну и ту же** схему таблицы `users`, и отдавать **одинаковые** JSON-ответы.
>
> Реализуй:
>
> * миграции SQL (`db/migrations/001_init.sql`) и сид SQL (`db/seed/001_seed_users.sql`) на 10k пользователей через `generate_series`;
> * эндпоинты `GET /healthz`, `GET /users/{id}`, `GET /users?limit&offset` (и опционально `/users/by-email`);
> * Dockerfile для каждого сервиса и `docker-compose.yml` (postgres + migrate + seed + go-api + py-api) с env-настройками пулов;
> * `loadtest/k6/` сценарии `read_user.js`, `list_users.js`, `mixed.js` с параметром `BASE_URL`;
> * `Makefile` с целями `up`, `up-go`, `up-py`, `bench-go`, `bench-py`, `down`, `clean`;
> * `README.md` с быстрым стартом и примером запуска нагрузочных тестов.
>
> Условия: по умолчанию отключи подробные логи, добавь таймауты серверов, сделай конфиг через `.env.example`. Результаты k6 сохраняй в `loadtest/results/*.json`.

---

Если хочешь, я сразу добавлю в ТЗ **точные значения** для пулов/воркеров и “дефолтные” профили нагрузок (чтобы было максимально воспроизводимо на твоём железе), но даже в текущем виде агент сможет собрать репу и ты начнёшь гонять сравнение.

[1]: https://grafana.com/docs/k6/latest/release-notes/?utm_source=chatgpt.com "Grafana k6 release notes"
[2]: https://docs.pydantic.dev/latest/?utm_source=chatgpt.com "Welcome to Pydantic - Pydantic Validation"
[3]: https://fastapi.tiangolo.com/release-notes/?utm_source=chatgpt.com "Release Notes - FastAPI"
[4]: https://github.com/go-chi/chi/releases?utm_source=chatgpt.com "Releases · go-chi/chi"
[5]: https://go.dev/doc/devel/release?utm_source=chatgpt.com "Release History"
[6]: https://github.com/go-chi/chi?utm_source=chatgpt.com "go-chi/chi: lightweight, idiomatic and composable router for ..."
[7]: https://k6.io/?utm_source=chatgpt.com "Grafana k6: Load testing for engineering teams"
