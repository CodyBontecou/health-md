## Health.md — developer commands
##
## Usage:
##   make test          run tests on both iOS simulator and macOS
##   make test-ios      run tests on iOS simulator only
##   make test-macos    run tests on macOS only

HOST_ARCH   := $(shell uname -m)
PROJECT     := HealthMd.xcodeproj
IOS_SIM     ?= platform=iOS Simulator,name=iPhone 16 Pro,arch=$(HOST_ARCH)
MACOS_DEST  ?= platform=macOS,arch=$(HOST_ARCH)
XCODE_TEST_SIGNING_FLAGS := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""

.PHONY: test test-ios test-macos

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
