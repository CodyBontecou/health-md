## Health.md — developer commands
##
## Usage:
##   make test              run tests on both iOS simulator and macOS
##   make test-ios          run tests on iOS simulator only
##   make test-macos        run tests on macOS only
##   make coverage          run tests with coverage collection (macOS)
##   make coverage-report   generate coverage summary from last run
##   make check-coverage    enforce coverage threshold from last run
##   make check-warnings    check build log for targeted warnings
##   make check-tdd         verify completed testing todos have TDD evidence

HOST_ARCH   := $(shell uname -m)
PROJECT     := HealthMd.xcodeproj
IOS_SIM     ?= platform=iOS Simulator,name=iPhone 16 Pro,arch=$(HOST_ARCH)
MACOS_DEST  ?= platform=macOS,arch=$(HOST_ARCH)
XCODE_TEST_SIGNING_FLAGS := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""

COVERAGE_DIR  := build/coverage
XCRESULT_PATH := $(COVERAGE_DIR)/HealthMd.xcresult

.PHONY: test test-ios test-macos coverage coverage-report check-coverage check-warnings check-tdd

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

check-tdd:
	@scripts/check-tdd-evidence.sh
