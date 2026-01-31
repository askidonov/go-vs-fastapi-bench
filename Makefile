.PHONY: help up up-go up-py down clean bench-go bench-py logs-go logs-py env

# Load .env file if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Default values
GO_PORT ?= 8080
PY_PORT ?= 8081

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

env: ## Copy .env.example to .env if not exists
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Created .env file from .env.example"; \
	else \
		echo ".env file already exists"; \
	fi

up: env ## Start all services (postgres + both APIs)
	docker compose --profile all up -d --build
	@echo "Waiting for services to be ready..."
	@sleep 5
	@echo "Services started!"
	@echo "Go API: http://localhost:$(GO_PORT)/healthz"
	@echo "Python API: http://localhost:$(PY_PORT)/healthz"

up-single: ## Start all services in SINGLE-INSTANCE mode (1 CPU, 1 worker)
	@echo "Using single-instance configuration (.env.single)"
	@cp .env.single .env
	docker compose -f docker-compose.yml -f docker-compose.single.yml --profile all up -d --build
	@echo "Waiting for services to be ready..."
	@sleep 5
	@echo "Services started in SINGLE-INSTANCE mode (1 CPU each)!"
	@echo "Go API: http://localhost:8080/healthz"
	@echo "Python API: http://localhost:8081/healthz"

up-multi: ## Start all services in MULTI-CORE mode (4 CPUs, 4 workers)
	@echo "Using multi-core configuration (.env.multi)"
	@cp .env.multi .env
	docker compose --profile all up -d --build
	@echo "Waiting for services to be ready..."
	@sleep 5
	@echo "Services started in MULTI-CORE mode (4 CPUs each)!"
	@echo "Go API: http://localhost:8080/healthz"
	@echo "Python API: http://localhost:8081/healthz"

up-go: env ## Start postgres + Go API only
	docker compose --profile go up -d --build
	@echo "Waiting for Go API to be ready..."
	@sleep 5
	@echo "Go API started: http://localhost:$(GO_PORT)/healthz"

up-py: env ## Start postgres + Python API only
	docker compose --profile py up -d --build
	@echo "Waiting for Python API to be ready..."
	@sleep 5
	@echo "Python API started: http://localhost:$(PY_PORT)/healthz"

down: ## Stop all services
	docker compose --profile all down

clean: ## Remove all containers and volumes (WARNING: deletes data!)
	docker compose --profile all down -v
	@echo "All containers and volumes removed"

logs-go: ## Show Go API logs
	docker compose logs -f go-api

logs-py: ## Show Python API logs
	docker compose logs -f py-api

bench-go: ## Run all k6 tests against Go API
	@echo "=== Running k6 tests for Go API ==="
	@chmod +x scripts/run_k6.sh
	@./scripts/run_k6.sh http://localhost:$(GO_PORT) read_user go
	@echo ""
	@./scripts/run_k6.sh http://localhost:$(GO_PORT) list_users go
	@echo ""
	@./scripts/run_k6.sh http://localhost:$(GO_PORT) mixed go
	@echo ""
	@echo "=== All Go API tests completed ==="

bench-py: ## Run all k6 tests against Python API
	@echo "=== Running k6 tests for Python API ==="
	@chmod +x scripts/run_k6.sh
	@./scripts/run_k6.sh http://localhost:$(PY_PORT) read_user py
	@echo ""
	@./scripts/run_k6.sh http://localhost:$(PY_PORT) list_users py
	@echo ""
	@./scripts/run_k6.sh http://localhost:$(PY_PORT) mixed py
	@echo ""
	@echo "=== All Python API tests completed ==="

bench-go-full: ## Run extended k6 tests for Go API (smoke, steady, ramp)
	@echo "=== Running extended k6 tests for Go API ==="
	@chmod +x scripts/run_k6.sh
	@./scripts/run_k6.sh http://localhost:$(GO_PORT) read_user go
	@echo ""
	@./scripts/run_k6.sh http://localhost:$(GO_PORT) steady go
	@echo ""
	@./scripts/run_k6.sh http://localhost:$(GO_PORT) ramp go
	@echo ""
	@echo "=== All extended Go API tests completed ==="

bench-py-full: ## Run extended k6 tests for Python API (smoke, steady, ramp)
	@echo "=== Running extended k6 tests for Python API ==="
	@chmod +x scripts/run_k6.sh
	@./scripts/run_k6.sh http://localhost:$(PY_PORT) read_user py
	@echo ""
	@./scripts/run_k6.sh http://localhost:$(PY_PORT) steady py
	@echo ""
	@./scripts/run_k6.sh http://localhost:$(PY_PORT) ramp py
	@echo ""
	@echo "=== All extended Python API tests completed ==="

test-go: ## Quick test of Go API endpoints
	@echo "Testing Go API..."
	@curl -s http://localhost:$(GO_PORT)/healthz | jq .
	@curl -s "http://localhost:$(GO_PORT)/users?limit=5" | jq '.items | length'

test-py: ## Quick test of Python API endpoints
	@echo "Testing Python API..."
	@curl -s http://localhost:$(PY_PORT)/healthz | jq .
	@curl -s "http://localhost:$(PY_PORT)/users?limit=5" | jq '.items | length'
