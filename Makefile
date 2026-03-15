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

.PHONY: setup extract migrate run-server run-test-server db db-stop redis redis-stop server-test server-test-db server-lint unit-test android-test ios-test android-unit-test kill-server clean run-android run-ios run-android-device run-ios-device package-ios publish-ios android-release-bundle publish-android

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

## run-server: Build and run the Go server (reads push config from .env)
run-server: .env setup extract
	@set -a && . $(CURDIR)/.env && set +a && cd server && go run ./cmd/server/... --db-dsn "$(DB_DSN)"

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

## redis: Start Redis in Docker for development
redis:
	docker run --name iceblox-redis -p 6379:6379 -d redis:7-alpine || docker start iceblox-redis

## redis-stop: Stop Redis container
redis-stop:
	docker stop iceblox-redis

# ── Run Apps ─────────────────────────────────────────────────────────────────

ANDROID_SDK := $(HOME)/Library/Android/sdk
ADB := $(ANDROID_SDK)/platform-tools/adb
EMULATOR_BIN := $(ANDROID_SDK)/emulator/emulator
ANDROID_AVD := Medium_Phone_API_36.1
ANDROID_PACKAGE := com.iceblox.app
ANDROID_ACTIVITY := .MainActivity

IOS_SIMULATOR_UDID := C06D96F6-6AE3-4B73-874F-C8324A15B0B9
IOS_BUNDLE_ID := com.iceblox.app
IOS_SCHEME := IceBloxApp
IOS_BUILD_DIR := ios/build

IOS_ARCHIVE := $(IOS_BUILD_DIR)/IceBloxApp.xcarchive
IOS_EXPORT_DIR := $(IOS_BUILD_DIR)/export
IOS_EXPORT_OPTIONS := $(IOS_BUILD_DIR)/ExportOptions.plist
APPLE_TEAM_ID ?= $(shell grep '^APPLE_TEAM_ID=' .env 2>/dev/null | cut -d= -f2)
APP_STORE_KEY_ID ?= $(shell grep '^APP_STORE_KEY_ID=' .env 2>/dev/null | cut -d= -f2)
APP_STORE_ISSUER_ID ?= $(shell grep '^APP_STORE_ISSUER_ID=' .env 2>/dev/null | cut -d= -f2)
APP_STORE_KEY_P8 ?= $(shell grep '^APP_STORE_KEY_P8=' .env 2>/dev/null | cut -d'"' -f2)
ALTOOL_KEY_DIR := ~/.appstoreconnect/private_keys

## package-ios: Archive and export a release .ipa for App Store upload
package-ios:
	@if [ -z "$(APPLE_TEAM_ID)" ]; then echo "ERROR: APPLE_TEAM_ID not set. Add APPLE_TEAM_ID=<your-team-id> to .env or pass it as an env var."; exit 1; fi
	@mkdir -p $(IOS_BUILD_DIR)
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>method</key>\n\t<string>app-store-connect</string>\n\t<key>signingStyle</key>\n\t<string>automatic</string>\n\t<key>teamID</key>\n\t<string>$(APPLE_TEAM_ID)</string>\n\t<key>uploadSymbols</key>\n\t<true/>\n</dict>\n</plist>\n' > $(IOS_EXPORT_OPTIONS)
	xcodebuild archive \
		-project ios/IceBloxApp.xcodeproj \
		-scheme $(IOS_SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath $(IOS_ARCHIVE) \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(APPLE_TEAM_ID) \
		OTHER_SWIFT_FLAGS="-DPRODUCTION_SERVER" \
		-quiet
	@echo "Patching embedded framework MinimumOSVersion..."
	@APP_MINOS=$$(plutil -extract MinimumOSVersion raw $(IOS_ARCHIVE)/Products/Applications/IceBloxApp.app/Info.plist); \
	for fw in $(IOS_ARCHIVE)/Products/Applications/IceBloxApp.app/Frameworks/*.framework; do \
		if [ -f "$$fw/Info.plist" ]; then \
			plutil -replace MinimumOSVersion -string "$$APP_MINOS" "$$fw/Info.plist"; \
			echo "  Set $$(basename $$fw) MinimumOSVersion to $$APP_MINOS"; \
		fi; \
	done
	xcodebuild -exportArchive \
		-archivePath $(IOS_ARCHIVE) \
		-exportPath $(IOS_EXPORT_DIR) \
		-exportOptionsPlist $(IOS_EXPORT_OPTIONS) \
		-allowProvisioningUpdates \
		-quiet
	@echo ""
	@echo "IPA ready at: $(IOS_EXPORT_DIR)/IceBloxApp.ipa"
	@echo "Upload with: make publish-ios"

## publish-ios: Upload the .ipa to App Store Connect via altool
publish-ios:
	@if [ -z "$(APP_STORE_KEY_ID)" ]; then echo "ERROR: APP_STORE_KEY_ID not set. Add APP_STORE_KEY_ID=<your-key-id> to .env or pass it as an env var."; exit 1; fi
	@if [ -z "$(APP_STORE_ISSUER_ID)" ]; then echo "ERROR: APP_STORE_ISSUER_ID not set. Add APP_STORE_ISSUER_ID=<your-issuer-id> to .env or pass it as an env var."; exit 1; fi
	@if [ -z "$(APP_STORE_KEY_P8)" ]; then echo "ERROR: APP_STORE_KEY_P8 not set. Add APP_STORE_KEY_P8=\"<pem-contents>\" to .env or pass it as an env var."; exit 1; fi
	@if [ ! -f "$(IOS_EXPORT_DIR)/IceBloxApp.ipa" ]; then echo "ERROR: IPA not found at $(IOS_EXPORT_DIR)/IceBloxApp.ipa. Run 'make package-ios' first."; exit 1; fi
	@mkdir -p $(ALTOOL_KEY_DIR)
	@printf '%b\n' "$(APP_STORE_KEY_P8)" > $(ALTOOL_KEY_DIR)/AuthKey_$(APP_STORE_KEY_ID).p8
	xcrun altool --upload-app \
		-f $(IOS_EXPORT_DIR)/IceBloxApp.ipa \
		-t ios \
		--apiKey $(APP_STORE_KEY_ID) \
		--apiIssuer $(APP_STORE_ISSUER_ID)

## run-android: Build, install, and launch the Android app on an emulator
run-android: .env
	@source ~/.zshrc && cd android && ./gradlew assembleDebug --quiet
	@if ! $(ADB) devices 2>/dev/null | grep -q "emulator"; then \
		echo "Starting Android emulator..."; \
		$(EMULATOR_BIN) -avd $(ANDROID_AVD) &>/dev/null & \
		$(ADB) wait-for-device; \
		while [ "$$($(ADB) shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do sleep 1; done; \
		echo "Emulator booted."; \
	fi
	$(ADB) install -r android/app/build/outputs/apk/debug/app-debug.apk
	$(ADB) shell am start -n $(ANDROID_PACKAGE)/$(ANDROID_ACTIVITY)

## run-ios: Build, install, and launch the iOS app on a simulator
run-ios:
	@if ! xcrun simctl list devices booted 2>/dev/null | grep -q "$(IOS_SIMULATOR_UDID)"; then \
		echo "Booting iOS simulator..."; \
		xcrun simctl boot "$(IOS_SIMULATOR_UDID)"; \
		open -a Simulator; \
		sleep 2; \
		echo "Simulator booted."; \
	fi
	xcodebuild build \
		-project ios/IceBloxApp.xcodeproj \
		-scheme $(IOS_SCHEME) \
		-destination "platform=iOS Simulator,id=$(IOS_SIMULATOR_UDID)" \
		-derivedDataPath $(IOS_BUILD_DIR) \
		-quiet
	xcrun simctl install "$(IOS_SIMULATOR_UDID)" \
		$$(find $(IOS_BUILD_DIR) -name "$(IOS_SCHEME).app" -path "*/Debug-iphonesimulator/*" | head -1)
	xcrun simctl launch "$(IOS_SIMULATOR_UDID)" $(IOS_BUNDLE_ID)

PROD_SERVER ?=
PROD_FLAG := $(if $(filter true,$(PROD_SERVER)),--prod-server)

## run-android-device: Build, install, and launch Android app on a connected device (PROD_SERVER=true for prod)
run-android-device: .env
	bash scripts/android-test.sh $(PROD_FLAG)

## run-ios-device: Build, install, and launch iOS app on a connected device (PROD_SERVER=true for prod)
run-ios-device:
	bash scripts/ios-test.sh $(PROD_FLAG)

# ── Tests ────────────────────────────────────────────────────────────────────

## unit-test: Run Go, Android, and iOS unit tests back to back
unit-test: server-test android-unit-test ios-unit-test

## android-release-bundle: Build a signed release AAB for Play Store upload
android-release-bundle: .env
	cd android && ./gradlew bundleRelease

## publish-android: Build a signed release AAB for Play Store upload
publish-android: android-release-bundle
	@AAB=$$(find android/app/build/outputs/bundle/release -name '*.aab' 2>/dev/null | head -1); \
	if [ -z "$$AAB" ]; then echo "ERROR: No AAB found"; exit 1; fi; \
	echo ""; \
	echo "Release AAB ready at: $$AAB"; \
	echo "Upload to Google Play Console to publish."

## android-unit-test: Run Android unit tests (generates .env first)
android-unit-test: .env
	cd android && ./gradlew test

## ios-unit-test: Run iOS unit tests
ios-unit-test:
	cd ios && xcodebuild test \
		-project IceBloxApp.xcodeproj \
		-scheme IceBloxApp \
		-destination 'platform=iOS Simulator,name=iPhone 16' \
		-quiet

## android-test: Run Android E2E tests
android-test: .env
	bash e2e/android/run.sh

## ios-test: Run iOS E2E tests
ios-test: .env
	bash e2e/ios/run.sh

# ── Cleanup ─────────────────────────────────────────────────────────────────

## clean: Remove downloaded data
clean:
	rm -rf $(DATA_DIR)
