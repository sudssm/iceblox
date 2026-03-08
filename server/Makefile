DATA_DIR := data
PLATES_FILE := $(DATA_DIR)/plates.txt
ZIP_FILE := $(DATA_DIR)/plates.zip
TRACKER_URL := https://www.stopice.net/platetracker

DB_DSN ?= postgres://$(USER)@localhost:5432/cameras?sslmode=disable
TEST_DB ?= cameras_test

.PHONY: setup extract run-server run-test-server db db-stop test test-db clean

## setup: Download the latest ICE plate data ZIP from StopICE
setup:
	mkdir -p $(DATA_DIR)
	@echo "Fetching latest download link from StopICE..."
	$(eval ZIP_NAME := $(shell curl -sL "$(TRACKER_URL)/?data=1" | sed -n 's/.*href="\(stopice_platetracker_compiled\/[^"]*\.zip\)".*/\1/p' | head -1))
	@if [ -z "$(ZIP_NAME)" ]; then echo "ERROR: could not find ZIP download link"; exit 1; fi
	@echo "Downloading $(ZIP_NAME)..."
	curl -L "$(TRACKER_URL)/$(ZIP_NAME)" -o $(ZIP_FILE)
	@echo "Downloaded to $(ZIP_FILE) ($$(du -h $(ZIP_FILE) | cut -f1))"

## extract: Parse the XML from the ZIP and produce plates.txt (one plate per line, normalized)
extract: $(ZIP_FILE)
	@echo "Extracting plates from XML..."
	unzip -p $(ZIP_FILE) "*.xml" \
		| sed -n 's/.*<vehicle_license>\(.*\)<\/vehicle_license>.*/\1/p' \
		| sed 's/[[:space:]-]//g' \
		| tr '[:lower:]' '[:upper:]' \
		| sort -u \
		| grep -E '^[A-Z0-9]{2,8}$$' \
		> $(PLATES_FILE)
	@echo "Extracted $$(wc -l < $(PLATES_FILE) | tr -d ' ') unique plates to $(PLATES_FILE)"

## run-server: Build and run the Go server
run-server:
	go run ./cmd/server/... --db-dsn "$(DB_DSN)"

## run-test-server: Run server with test plates (known plates for E2E testing)
run-test-server:
	go run ./cmd/server/... --plates-file testdata/test_plates.txt --db-dsn "$(DB_DSN)"

## test: Run all Go tests (unit only, no DB required)
test:
	go test ./...

## test-db: Run all tests including DB integration tests (requires PostgreSQL)
test-db:
	@dropdb --if-exists $(TEST_DB) 2>/dev/null; \
	createdb $(TEST_DB) && \
	TEST_DATABASE_URL="postgres://$(USER)@localhost:5432/$(TEST_DB)?sslmode=disable" go test -tags integration ./... -v; \
	dropdb --if-exists $(TEST_DB)

## db: Start PostgreSQL in Docker for development
db:
	docker run --name cameras-postgres -e POSTGRES_DB=cameras -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=cameras -p 5432:5432 -d postgres:16-alpine || docker start cameras-postgres

## db-stop: Stop PostgreSQL container
db-stop:
	docker stop cameras-postgres

## clean: Remove downloaded data
clean:
	rm -rf $(DATA_DIR)
