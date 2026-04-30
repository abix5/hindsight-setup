.PHONY: start stop restart status logs logs-api logs-ui health install sync-version

-include .env
VERSION ?= latest
VERSION_CLEAN := $(patsubst v%,%,$(strip $(VERSION)))

VENV     := .venv-hs
API      := $(VENV)/bin/hindsight-api
PIDFILE  := /tmp/hindsight-api.pid
LOGDIR   := ./logs
API_LOG  := $(LOGDIR)/api.log
UI_LOG   := $(LOGDIR)/ui.log
API_PORT := 8888
UI_PORT  := 9999
MAX_LOGS := 3
VERSION_FILE := $(VENV)/.hindsight-version
PYTHON_PACKAGE := hindsight-all
UI_PACKAGE := @vectorize-io/hindsight-control-plane
UI_PACKAGE_SPEC := $(if $(filter latest,$(VERSION_CLEAN)),$(UI_PACKAGE),$(UI_PACKAGE)@$(VERSION_CLEAN))

# ── Primary commands ─────────────────────────────────

start: _db _rotate sync-version _api _ui _wait  ## Start everything (DB + API + UI)
	@echo ""
	@echo "  API  http://localhost:$(API_PORT)"
	@echo "  UI   http://localhost:$(UI_PORT)"
	@echo "  MCP  http://localhost:$(API_PORT)/mcp/{bank_id}/"
	@echo "  Logs: make logs"
	@echo ""

stop:  ## Stop API and UI
	@-lsof -ti:$(API_PORT) | xargs kill 2>/dev/null; echo "API stopped"
	@-lsof -ti:$(UI_PORT)  | xargs kill 2>/dev/null; echo "UI  stopped"
	@rm -f $(PIDFILE)

stop-all: stop  ## Stop everything including PostgreSQL
	docker compose stop postgres
	@echo "PostgreSQL stopped"

restart: stop start  ## Restart API + UI

status:  ## Show what is running
	@echo "--- PostgreSQL ---"
	@docker compose ps postgres 2>/dev/null || echo "not running"
	@echo ""
	@echo "--- API (port $(API_PORT)) ---"
	@lsof -ti:$(API_PORT) >/dev/null 2>&1 && echo "running (PID $$(lsof -ti:$(API_PORT)))" || echo "not running"
	@echo ""
	@echo "--- UI (port $(UI_PORT)) ---"
	@lsof -ti:$(UI_PORT) >/dev/null 2>&1 && echo "running (PID $$(lsof -ti:$(UI_PORT)))" || echo "not running"

health:  ## Quick health check
	@curl -sf http://localhost:$(API_PORT)/health && echo "" || echo "API not responding"

logs:  ## Tail API + UI logs together (colored)
	@echo "Ctrl+C to stop. Showing: $(API_LOG) + $(UI_LOG)"
	@echo "────────────────────────────────────────"
	@tail -f $(API_LOG) $(UI_LOG) 2>/dev/null \
		| sed -u \
			-e 's|^==> .*/api.log <==|———— API ————|' \
			-e 's|^==> .*/ui.log <==|———— UI  ————|'

logs-api:  ## Tail API log only
	@tail -f $(API_LOG)

logs-ui:  ## Tail UI log only
	@tail -f $(UI_LOG)

install:  ## One-time setup: create venv and install hindsight
	uv python install 3.11
	uv venv --python 3.11 $(VENV)
	@$(MAKE) sync-version
	@echo "Done. Run: make start"

sync-version:  ## Sync installed API and UI versions to VERSION
	@if [ ! -x "$(VENV)/bin/python" ]; then \
		echo "Creating virtualenv $(VENV)..."; \
		uv python install 3.11; \
		uv venv --python 3.11 $(VENV); \
	fi
	@INSTALLED=$$("$(VENV)/bin/python" -c "import importlib.metadata as m; print(m.version('$(PYTHON_PACKAGE)'))" 2>/dev/null || echo "missing"); \
	RECORDED=$$(cat "$(VERSION_FILE)" 2>/dev/null || echo "missing"); \
	if [ "$(VERSION_CLEAN)" = "latest" ]; then \
		if [ "$$INSTALLED" = "missing" ] || [ "$$RECORDED" != "latest" ]; then \
			echo "Python: syncing $(PYTHON_PACKAGE) to latest"; \
			uv pip install --python $(VENV)/bin/python --upgrade "$(PYTHON_PACKAGE)"; \
			echo "latest" > "$(VERSION_FILE)"; \
		else \
			echo "Python: $(PYTHON_PACKAGE) already synced to latest policy ($$INSTALLED)"; \
		fi; \
	else \
		if [ "$$INSTALLED" != "$(VERSION_CLEAN)" ] || [ "$$RECORDED" != "$(VERSION_CLEAN)" ]; then \
			echo "Python: syncing $(PYTHON_PACKAGE) $$INSTALLED -> $(VERSION_CLEAN)"; \
			uv pip install --python $(VENV)/bin/python "$(PYTHON_PACKAGE)==$(VERSION_CLEAN)"; \
			echo "$(VERSION_CLEAN)" > "$(VERSION_FILE)"; \
		else \
			echo "Python: $(PYTHON_PACKAGE) already at $(VERSION_CLEAN)"; \
		fi; \
	fi
	@echo "UI: using $(UI_PACKAGE_SPEC)"

# ── Internal targets ─────────────────────────────────

_rotate:
	@mkdir -p $(LOGDIR)
	@# Rotate existing logs (keep last MAX_LOGS)
	@for f in $(API_LOG) $(UI_LOG); do \
		if [ -f "$$f" ] && [ -s "$$f" ]; then \
			i=$(MAX_LOGS); while [ $$i -gt 1 ]; do \
				prev=$$((i - 1)); \
				[ -f "$$f.$$prev" ] && mv "$$f.$$prev" "$$f.$$i"; \
				i=$$prev; \
			done; \
			mv "$$f" "$$f.1"; \
		fi; \
		rm -f "$$f.$$(($(MAX_LOGS) + 1))"; \
	done

_db:
	@docker compose up -d postgres >/dev/null 2>&1
	@echo "PostgreSQL: waiting for healthy..."
	@for i in $$(seq 1 30); do \
		docker compose exec -T postgres pg_isready -U hindsight -d hindsight_db >/dev/null 2>&1 && break; \
		sleep 1; \
	done
	@echo "PostgreSQL: ready"

_api:
	@if lsof -ti:$(API_PORT) >/dev/null 2>&1; then \
		echo "API: already running"; \
	else \
		echo "API: starting..."; \
		nohup $(API) --host 0.0.0.0 --port $(API_PORT) > $(API_LOG) 2>&1 & echo $$! > $(PIDFILE); \
	fi

_ui:
	@if lsof -ti:$(UI_PORT) >/dev/null 2>&1; then \
		echo "UI:  already running"; \
	elif ! command -v npx >/dev/null 2>&1; then \
		echo "UI:  skipped (npx not found — install Node.js)"; \
	else \
		echo "UI:  starting $(UI_PACKAGE_SPEC) (background)..."; \
		nohup npx -y $(UI_PACKAGE_SPEC) \
			--api-url http://localhost:$(API_PORT) --port $(UI_PORT) \
			> $(UI_LOG) 2>&1 & \
	fi

_wait:
	@echo "Waiting for API..."
	@for i in $$(seq 1 60); do \
		curl -sf http://localhost:$(API_PORT)/health >/dev/null 2>&1 && break; \
		sleep 1; \
	done
	@curl -sf http://localhost:$(API_PORT)/health >/dev/null 2>&1 \
		&& echo "API: ready" \
		|| (echo "API: failed to start — check: make logs"; exit 1)
