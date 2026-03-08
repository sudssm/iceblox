DATA_DIR := data
PLATES_FILE := $(DATA_DIR)/plates.txt
ZIP_FILE := $(DATA_DIR)/plates.zip
TRACKER_URL := https://www.stopice.net/platetracker

.PHONY: setup extract run-server clean

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
	go run ./cmd/server/...

## clean: Remove downloaded data
clean:
	rm -rf $(DATA_DIR)
