## Health.md — developer commands
##
## Usage:
##   make test              run tests on both iOS simulator and macOS
##   make test-ios          run tests on iOS simulator only
##   make test-macos        run tests on macOS only
##   make prepare-healthmd-core-rust
##                           generate-check, source-build, and validate the
##                           ignored static shared-core XCFramework
##   make test-tsan          run tests with Thread Sanitizer (macOS)
##   make coverage          run tests with coverage collection (macOS)
##   make coverage-report   generate coverage summary from last run
##   make check-coverage    enforce coverage threshold from last run
##   make check-warnings    check build log for targeted warnings
##   make check-apns-scheduling
##                           verify production APNs scheduled-export release config
##   make check-app-store-metadata
##                           validate canonical App Store metadata field limits and
##                           duplication rules
##   make check-macos-localizations
##                           validate production macOS catalog coverage and placeholders
##   make update-export-schema-signature
##                           refresh versioned export schema fingerprint fixture
##                           set ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE=1 only
##                           for pre-production schema fixture rewrites
##   make generate-export-docs
##                           regenerate all source-backed export reference artifacts
##   make check-export-docs  verify generated artifacts and local documentation links
##   make test-export-lab-tools
##                           run host runner and private API sink tests
##   make check-export-lab-release
##                           prove Debug lab control/telemetry is absent from Release
##   make test-cli           run standalone healthmd CLI tests
##   make cli                build the standalone healthmd CLI
##   make install-cli        install healthmd + healthmd-mcp to ~/.local/bin

SHELL       := /bin/bash
HOST_ARCH   := $(shell uname -m)
PROJECT     := HealthMd.xcodeproj
IOS_SIM     ?=
MACOS_DEST  ?= platform=macOS,arch=$(HOST_ARCH)
XCODE_TEST_SIGNING_FLAGS := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
XCODE_TEST_TIMEOUT_FLAGS := -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300
CLI_INSTALL_DIR ?= $(HOME)/.local/bin
CORE_RUST_PREPARE := ../../packages/healthmd-core-rust/scripts/prepare-apple-xcframework.sh

TEST_RESULTS_DIR   := build/test-results
IOS_XCRESULT_PATH  ?= $(TEST_RESULTS_DIR)/HealthMd-iOS.xcresult
IOS_TEST_RAW_LOG   ?= build/logs/xcodebuild-ios-raw.log
COVERAGE_DIR       := build/coverage
XCRESULT_PATH      := $(COVERAGE_DIR)/HealthMd.xcresult

.PHONY: test test-ios test-macos prepare-healthmd-core-rust test-tsan coverage coverage-report check-coverage check-warnings check-apns-scheduling check-app-store-metadata check-macos-localizations update-export-schema-signature generate-export-docs check-export-docs test-cli cli install-cli test-export-lab-tools check-export-lab-release

prepare-healthmd-core-rust:
	@$(CORE_RUST_PREPARE)

test: test-ios test-macos

check-macos-localizations:
	@python3 -m unittest discover -s scripts/tests -p 'test_validate_macos_localizations.py'
	@python3 scripts/validate-macos-localizations.py

check-app-store-metadata:
	@python3 -m unittest discover -s scripts/tests -p 'test_validate_app_store_metadata.py'
	@python3 scripts/validate-app-store-metadata.py

test-ios: prepare-healthmd-core-rust
	@echo "\n━━━  iOS Tests  ━━━"
	@mkdir -p $(TEST_RESULTS_DIR) "$(dir $(IOS_TEST_RAW_LOG))"
	@rm -rf "$(IOS_XCRESULT_PATH)" "$(IOS_TEST_RAW_LOG)"
	@set -o pipefail; \
	  ios_sim='$(IOS_SIM)'; \
	  if [[ -z "$$ios_sim" ]]; then \
	    ios_sim="$$(scripts/select-ios-simulator.sh)"; \
	  fi; \
	  echo "Using iOS Simulator destination: $$ios_sim"; \
	  xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-iOS \
	  -destination "$$ios_sim" \
	  -configuration Debug-iOS \
	  -resultBundlePath "$(IOS_XCRESULT_PATH)" \
	  -test-timeouts-enabled NO \
	  $(XCODE_TEST_SIGNING_FLAGS) \
	  2>&1 | tee "$(IOS_TEST_RAW_LOG)" | \
	  if command -v xcpretty >/dev/null 2>&1; then \
	    xcpretty --color; \
	  else \
	    grep -E "Test Case|error:|PASSED|FAILED|Executed|Testing failed|Test session results|TEST (SUCCEEDED|FAILED)"; \
	  fi

test-macos: prepare-healthmd-core-rust
	@echo "\n━━━  macOS Tests  ━━━"
	@set -o pipefail; \
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-macOS \
	  -destination '$(MACOS_DEST)' \
	  $(XCODE_TEST_TIMEOUT_FLAGS) \
	  $(XCODE_TEST_SIGNING_FLAGS) \
	  2>&1 | \
	  if command -v xcpretty >/dev/null 2>&1; then \
	    xcpretty --color; \
	  else \
	    grep -E "Test Case|error:|PASSED|FAILED|Executed"; \
	  fi

test-tsan: prepare-healthmd-core-rust
	@echo "\n━━━  macOS Tests (Thread Sanitizer)  ━━━"
	@echo "NOTE: TSan requires x86_64; not supported for arm64-apple-ios targets."
	@echo "If this fails with 'unsupported option -fsanitize=thread', the project's"
	@echo "iOS target dependencies prevent TSan on Apple Silicon. See lifecycle-audit.md."
	@set -o pipefail; \
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-macOS \
	  -destination '$(MACOS_DEST)' \
	  -enableThreadSanitizer YES \
	  $(XCODE_TEST_TIMEOUT_FLAGS) \
	  $(XCODE_TEST_SIGNING_FLAGS) \
	  2>&1 | \
	  if command -v xcpretty >/dev/null 2>&1; then \
	    xcpretty --color; \
	  else \
	    grep -E "Test Case|error:|PASSED|FAILED|Executed"; \
	  fi

coverage: prepare-healthmd-core-rust
	@echo "\n━━━  macOS Tests with Coverage  ━━━"
	@mkdir -p $(COVERAGE_DIR)
	@rm -rf $(XCRESULT_PATH)
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-macOS \
	  -destination '$(MACOS_DEST)' \
	  -enableCodeCoverage YES \
	  -resultBundlePath $(XCRESULT_PATH) \
	  $(XCODE_TEST_TIMEOUT_FLAGS) \
	  $(XCODE_TEST_SIGNING_FLAGS)
	@$(MAKE) coverage-report

coverage-report:
	@echo "\n━━━  Coverage Summary  ━━━"
	@xcrun xccov view --report --only-targets $(XCRESULT_PATH) 2>/dev/null || \
	  echo "No coverage data found. Run 'make coverage' first."

check-coverage:
	@scripts/check-coverage.sh $(XCRESULT_PATH)

check-warnings:
	@scripts/check-warnings.sh build/logs/build-test.log

check-apns-scheduling:
	@scripts/check-apns-scheduling-preflight.sh

update-export-schema-signature:
	@scripts/update-export-schema-signature.sh

generate-export-docs:
	@scripts/generated-export-docs.sh update
	@scripts/generated-individual-entry-docs.sh update
	@scripts/generated-rollup-reference-docs.sh update
	@scripts/generated-automation-reference-docs.sh update
	@scripts/generated-cli-reference-docs.sh update
	@scripts/check-documentation-links.py

check-export-docs:
	@scripts/generated-export-docs.sh check
	@scripts/generated-individual-entry-docs.sh check
	@scripts/generated-rollup-reference-docs.sh check
	@scripts/generated-automation-reference-docs.sh check
	@scripts/generated-cli-reference-docs.sh check
	@scripts/check-documentation-links.py

test-export-lab-tools:
	python3 -m unittest discover -s scripts/tests -p 'test_export_performance_*.py' -v

check-export-lab-release:
	rm -rf build/ExportLabRelease
	xcodebuild build -project HealthMd.xcodeproj -scheme HealthMd \
		-configuration Release-iOS -destination 'generic/platform=iOS' \
		-derivedDataPath build/ExportLabRelease \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
		DEVELOPMENT_TEAM='' PROVISIONING_PROFILE_SPECIFIER=''
	xcodebuild build -project HealthMd.xcodeproj -scheme HealthMd-macOS \
		-configuration Release -destination 'platform=macOS,arch=$(HOST_ARCH)' \
		-derivedDataPath build/ExportLabRelease \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
		DEVELOPMENT_TEAM='' PROVISIONING_PROFILE_SPECIFIER=''
	@scripts/check-export-lab-release-absence.sh \
		build/ExportLabRelease/Build/Products/Release-iOS-iphoneos/HealthMd.app/HealthMd \
		build/ExportLabRelease/Build/Products/Release/Health.md.app/Contents/MacOS/Health.md

test-cli:
	swift test --package-path HealthMdCLI

cli:
	swift build --package-path HealthMdCLI -c release

install-cli: cli
	@mkdir -p "$(CLI_INSTALL_DIR)"
	@cp HealthMdCLI/.build/release/healthmd "$(CLI_INSTALL_DIR)/healthmd"
	@cp HealthMdCLI/.build/release/healthmd-mcp "$(CLI_INSTALL_DIR)/healthmd-mcp"
	@chmod 755 "$(CLI_INSTALL_DIR)/healthmd" "$(CLI_INSTALL_DIR)/healthmd-mcp"
	@codesign --force --sign - --options runtime --entitlements HealthMdCLI/healthmd.entitlements "$(CLI_INSTALL_DIR)/healthmd"
	@codesign --force --sign - --options runtime --entitlements HealthMdCLI/healthmd-mcp.entitlements "$(CLI_INSTALL_DIR)/healthmd-mcp"
	@echo "Installed signed healthmd and sandboxed healthmd-mcp to $(CLI_INSTALL_DIR)"
