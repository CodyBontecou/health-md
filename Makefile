## Health.md — developer commands
##
## Usage:
##   make test              run tests on both iOS simulator and macOS
##   make test-ios          run tests on iOS simulator only
##   make test-macos        run tests on macOS only
##   make test-tsan          run tests with Thread Sanitizer (macOS)
##   make coverage          run tests with coverage collection (macOS)
##   make coverage-report   generate coverage summary from last run
##   make check-coverage    enforce coverage threshold from last run
##   make check-warnings    check build log for targeted warnings
##   make check-apns-scheduling
##                           verify production APNs scheduled-export release config
##   make update-export-schema-signature
##                           refresh versioned export schema fingerprint fixture
##                           set ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE=1 only
##                           for pre-production schema fixture rewrites
##   make cli                build the standalone healthmd CLI
##   make install-cli        install the standalone CLI to ~/.local/bin/healthmd

HOST_ARCH   := $(shell uname -m)
PROJECT     := HealthMd.xcodeproj
IOS_SIM     ?= platform=iOS Simulator,name=iPhone 16 Pro,arch=$(HOST_ARCH)
MACOS_DEST  ?= platform=macOS,arch=$(HOST_ARCH)
XCODE_TEST_SIGNING_FLAGS := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
CLI_INSTALL_DIR ?= $(HOME)/.local/bin

COVERAGE_DIR  := build/coverage
XCRESULT_PATH := $(COVERAGE_DIR)/HealthMd.xcresult

.PHONY: test test-ios test-macos test-tsan coverage coverage-report check-coverage check-warnings check-apns-scheduling update-export-schema-signature cli install-cli

test: test-ios test-macos

test-ios:
	@echo "\n━━━  iOS Tests  ━━━"
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-iOS \
	  -destination '$(IOS_SIM)' \
	  -configuration Debug-iOS \
	  $(XCODE_TEST_SIGNING_FLAGS) \
	  | xcpretty --color 2>/dev/null || \
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-iOS \
	  -destination '$(IOS_SIM)' \
	  -configuration Debug-iOS \
	  $(XCODE_TEST_SIGNING_FLAGS) \
	  | grep -E "Test Case|error:|PASSED|FAILED|Executed"

test-macos:
	@echo "\n━━━  macOS Tests  ━━━"
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-macOS \
	  -destination '$(MACOS_DEST)' \
	  $(XCODE_TEST_SIGNING_FLAGS) \
	  | xcpretty --color 2>/dev/null || \
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-macOS \
	  -destination '$(MACOS_DEST)' \
	  $(XCODE_TEST_SIGNING_FLAGS) \
	  | grep -E "Test Case|error:|PASSED|FAILED|Executed"

test-tsan:
	@echo "\n━━━  macOS Tests (Thread Sanitizer)  ━━━"
	@echo "NOTE: TSan requires x86_64; not supported for arm64-apple-ios targets."
	@echo "If this fails with 'unsupported option -fsanitize=thread', the project's"
	@echo "iOS target dependencies prevent TSan on Apple Silicon. See lifecycle-audit.md."
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-macOS \
	  -destination '$(MACOS_DEST)' \
	  -enableThreadSanitizer YES \
	  $(XCODE_TEST_SIGNING_FLAGS) \
	  | xcpretty --color 2>/dev/null || \
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-macOS \
	  -destination '$(MACOS_DEST)' \
	  -enableThreadSanitizer YES \
	  $(XCODE_TEST_SIGNING_FLAGS) \
	  | grep -E "Test Case|error:|PASSED|FAILED|Executed"

coverage:
	@echo "\n━━━  macOS Tests with Coverage  ━━━"
	@mkdir -p $(COVERAGE_DIR)
	@rm -rf $(XCRESULT_PATH)
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-macOS \
	  -destination '$(MACOS_DEST)' \
	  -enableCodeCoverage YES \
	  -resultBundlePath $(XCRESULT_PATH) \
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

cli:
	swift build --package-path HealthMdCLI -c release

install-cli: cli
	@mkdir -p "$(CLI_INSTALL_DIR)"
	@cp HealthMdCLI/.build/release/healthmd "$(CLI_INSTALL_DIR)/healthmd"
	@chmod 755 "$(CLI_INSTALL_DIR)/healthmd"
	@echo "Installed healthmd to $(CLI_INSTALL_DIR)/healthmd"
