PEPPER ?= $(shell grep '^PEPPER=' .env 2>/dev/null | cut -d= -f2)
export PEPPER

.env: pepper.config
	@grep -q '^PEPPER=' .env 2>/dev/null || cat pepper.config >> .env

# ── Server ──────────────────────────────────────────────────────────────────

DATA_DIR := server/data
PLATES_FILE := $(DATA_DIR)/plates.txt
ZIP_FILE := $(DATA_DIR)/plates.zip
ZIP_URL_FILE := $(DATA_DIR)/.zip_url
TRACKER_URL := https://www.stopice.net/platetracker

DB_DSN ?= postgres://postgres:iceblox@localhost:5432/iceblox?sslmode=disable
TEST_DB ?= iceblox_test

.PHONY: setup extract migrate run-server run-test-server db db-stop server-test server-test-db server-lint android-test kill-server clean

## setup: Download the latest ICE plate data ZIP from StopICE (skips if source unchanged)
setup:
	@mkdir -p $(DATA_DIR)
	@echo "Checking for latest download link from StopICE..."
	$(eval ZIP_NAME := $(shell curl -sL "$(TRACKER_URL)/?data=1" | sed -n 's/.*href="\(stopice_platetracker_compiled\/[^"]*\.zip\)".*/\1/p' | head -1))
	@if [ -z "$(ZIP_NAME)" ]; then echo "ERROR: could not find ZIP download link"; exit 1; fi
	@if [ -f $(ZIP_FILE) ] && [ -f $(ZIP_URL_FILE) ] && [ "$$(cat $(ZIP_URL_FILE))" = "$(ZIP_NAME)" ]; then \
		echo "plates.zip is already up to date ($(ZIP_NAME))"; \
	else \
		echo "Downloading $(ZIP_NAME)..."; \
		curl -L "$(TRACKER_URL)/$(ZIP_NAME)" -o $(ZIP_FILE); \
		echo "$(ZIP_NAME)" > $(ZIP_URL_FILE); \
		echo "Downloaded to $(ZIP_FILE) ($$(du -h $(ZIP_FILE) | cut -f1))"; \
	fi

## extract: Parse the XML from the ZIP and produce plates.txt (one plate per line, normalized)
extract: $(PLATES_FILE)
$(PLATES_FILE): $(ZIP_FILE)
	@echo "Extracting plates from XML..."
	unzip -p $(ZIP_FILE) "*.xml" \
		| sed -n 's/.*<vehicle_license>\(.*\)<\/vehicle_license>.*/\1/p' \
		| sed 's/[[:space:]-]//g' \
		| tr '[:lower:]' '[:upper:]' \
		| sort -u \
		| grep -E '^[A-Z0-9]{2,8}$$' \
		> $(PLATES_FILE)
	@echo "Extracted $$(wc -l < $(PLATES_FILE) | tr -d ' ') unique plates to $(PLATES_FILE)"

## migrate: Run database schema migrations without starting the server
migrate:
	@if [ -x /server ]; then \
		/server --migrate-only --db-dsn "$${DATABASE_URL:-$(DB_DSN)}"; \
	else \
		cd server && go run ./cmd/server/... --migrate-only --db-dsn "$${DATABASE_URL:-$(DB_DSN)}"; \
	fi

FCM_SERVICE_ACCOUNT ?=
APNS_KEY_FILE ?=

## run-server: Build and run the Go server
run-server:
	cd server && go run ./cmd/server/... --db-dsn "$(DB_DSN)" \
		$(if $(FCM_SERVICE_ACCOUNT),--fcm-service-account "$(FCM_SERVICE_ACCOUNT)") \
		$(if $(APNS_KEY_FILE),--apns-key-file "$(APNS_KEY_FILE)")

## run-test-server: Run server with test plates (known plates for E2E testing)
run-test-server:
	cd server && go run ./cmd/server/... --plates-file testdata/test_plates.txt --db-dsn "$(DB_DSN)"

## server-lint: Run golangci-lint
server-lint:
	cd server && golangci-lint run ./...

## server-test: Run all Go tests (unit only, no DB required)
server-test:
	cd server && go test ./...

## server-test-db: Run all tests including DB integration tests (requires PostgreSQL)
server-test-db:
	@dropdb --if-exists $(TEST_DB) 2>/dev/null; \
	createdb $(TEST_DB) && \
	cd server && TEST_DATABASE_URL="postgres://$(USER)@localhost:5432/$(TEST_DB)?sslmode=disable" go test -tags integration ./... -v; \
	dropdb --if-exists $(TEST_DB)

## kill-server: Kill whatever is listening on port 8080
kill-server:
	@lsof -ti :8080 | xargs kill -9 2>/dev/null && echo "Killed process on port 8080" || echo "Nothing listening on port 8080"

## db: Start PostgreSQL in Docker for development
db:
	docker run --name iceblox-postgres -e POSTGRES_DB=iceblox -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=iceblox -p 5432:5432 -d postgres:16-alpine || docker start iceblox-postgres

## db-stop: Stop PostgreSQL container
db-stop:
	docker stop iceblox-postgres

# ── Android ─────────────────────────────────────────────────────────────────

## android-test: Run Android unit tests (generates .env first)
android-test: .env
	cd android && ./gradlew test

# ── Cleanup ─────────────────────────────────────────────────────────────────

## clean: Remove downloaded data
clean:
	rm -rf $(DATA_DIR)
