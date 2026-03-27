## Health.md — developer commands
##
## Usage:
##   make test          run tests on both iOS simulator and macOS
##   make test-ios      run tests on iOS simulator only
##   make test-macos    run tests on macOS only

PROJECT     := HealthMd.xcodeproj
IOS_SIM     := platform=iOS Simulator,name=iPhone 16 Pro
MACOS_DEST  := platform=macOS

.PHONY: test test-ios test-macos

test: test-ios test-macos

test-ios:
	@echo "\n━━━  iOS Tests  ━━━"
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-iOS \
	  -destination '$(IOS_SIM)' \
	  -configuration Debug-iOS \
	  | xcpretty --color 2>/dev/null || \
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-iOS \
	  -destination '$(IOS_SIM)' \
	  -configuration Debug-iOS \
	  | grep -E "Test Case|error:|PASSED|FAILED|Executed"

test-macos:
	@echo "\n━━━  macOS Tests  ━━━"
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-macOS \
	  -destination '$(MACOS_DEST)' \
	  | xcpretty --color 2>/dev/null || \
	xcodebuild test \
	  -project $(PROJECT) \
	  -scheme HealthMd-Tests-macOS \
	  -destination '$(MACOS_DEST)' \
	  | grep -E "Test Case|error:|PASSED|FAILED|Executed"
