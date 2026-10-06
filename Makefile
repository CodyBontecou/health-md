## Health.md monorepo command router

ANDROID_HOME ?= $(HOME)/Library/Android/sdk
CORE_RUST_DIR := packages/healthmd-core-rust
CORE_BINDINGS_DIR ?= $(CURDIR)/$(CORE_RUST_DIR)/target/generated-bindings
TEST_COMPONENTS := contracts core apple android cli practice wake website
.DEFAULT_GOAL := help

.PHONY: help test test-all test-testing-tools test-contracts test-product-parity test-core check-core-registry core-bindings check-core-bindings \
        test-apple test-android test-android-all test-cli test-practice test-wake test-website apple-ios apple-macos cli-build \
        android-build android-play-debug android-fdroid-debug android-fdroid-release \
        practice-build website-build

help:
	@echo 'Choose a component: make test COMPONENT=<$(TEST_COMPONENTS)>'
	@echo 'Focused iteration commands: docs/testing-strategy.md'
	@echo 'Host-side orchestration checks: make test-testing-tools'
	@echo 'Explicit broad smoke sweep (not release qualification): make test-all'

# Require an explicit owner rather than silently qualifying the monorepo.
test:
ifneq ($(words $(COMPONENT)),1)
	@echo 'Set exactly one COMPONENT: $(TEST_COMPONENTS)' >&2
	@exit 2
else ifeq ($(filter $(TEST_COMPONENTS),$(COMPONENT)),)
	@echo 'Unknown COMPONENT; choose one of: $(TEST_COMPONENTS)' >&2
	@exit 2
else
	$(MAKE) test-$(COMPONENT)
endif

test-all: test-contracts test-core test-apple test-android-all test-cli test-practice test-wake test-website

test-testing-tools:
	python3 -m unittest discover -s scripts/tests -p 'test_testing_*.py'
	python3 -m unittest discover -s apps/apple/scripts/tests -p test_testing_performance.py
	node --test apps/website/test/build-orchestration.test.mjs
	node --test scripts/tests/verification-*.test.mjs

test-contracts:
	python3 packages/contracts/validate.py

test-product-parity:
	python3 packages/contracts/validate.py --product-parity-only

test-core: check-core-registry
	cd $(CORE_RUST_DIR) && cargo test --workspace --all-features --locked

check-core-registry:
	python3 -m unittest discover -s $(CORE_RUST_DIR)/scripts/tests -p 'test_native_registry_import.py'
	python3 $(CORE_RUST_DIR)/scripts/import-native-registry.py --check
	python3 $(CORE_RUST_DIR)/scripts/generate-registry-adapters.py --check

core-bindings:
	$(CORE_RUST_DIR)/scripts/generate-swift-bindings.sh "$(CORE_BINDINGS_DIR)/swift"
	$(CORE_RUST_DIR)/scripts/generate-kotlin-bindings.sh "$(CORE_BINDINGS_DIR)/kotlin"

check-core-bindings:
	@set -eu; \
	check_dir="$(CURDIR)/$(CORE_RUST_DIR)/target/check-generated-bindings"; \
	trap 'rm -rf "$$check_dir"' EXIT HUP INT TERM; \
	rm -rf "$$check_dir"; \
	$(CORE_RUST_DIR)/scripts/generate-swift-bindings.sh "$$check_dir/first/swift"; \
	$(CORE_RUST_DIR)/scripts/generate-kotlin-bindings.sh "$$check_dir/first/kotlin"; \
	$(CORE_RUST_DIR)/scripts/generate-swift-bindings.sh "$$check_dir/second/swift"; \
	$(CORE_RUST_DIR)/scripts/generate-kotlin-bindings.sh "$$check_dir/second/kotlin"; \
	test -n "$$(find "$$check_dir/first/swift" -type f -name '*.swift' -print -quit)"; \
	test -n "$$(find "$$check_dir/first/kotlin" -type f -name '*.kt' -print -quit)"; \
	diff -ru "$$check_dir/first" "$$check_dir/second"

test-apple:
	$(MAKE) -C apps/apple test

# Local regressions compile one app variant; CI still qualifies every flavor.
test-android:
	cd apps/android && ANDROID_HOME="$(ANDROID_HOME)" ./gradlew --no-daemon --max-workers=2 \
		:app:testPlayDebugUnitTest :healthmd-core:testDebugUnitTest \
		:wearable-contract:test :wear:testDebugUnitTest :direct-protocol:test

test-android-all:
	cd apps/android && ANDROID_HOME="$(ANDROID_HOME)" ./gradlew test

test-cli:
	cd apps/cli && cargo test --workspace --all-features --locked

test-practice:
	cd apps/practice && npm run check

test-wake:
	cd apps/wake && npm test && npm run check

test-website:
	cd apps/website && npm test

apple-ios:
	$(MAKE) -C apps/apple test-ios

apple-macos:
	$(MAKE) -C apps/apple test-macos

cli-build:
	cd apps/cli && cargo build --workspace

android-build: android-play-debug

android-play-debug:
	cd apps/android && ANDROID_HOME="$(ANDROID_HOME)" ./gradlew :app:assemblePlayDebug

android-fdroid-debug:
	cd apps/android && ANDROID_HOME="$(ANDROID_HOME)" ./gradlew :app:assembleFdroidDebug

android-fdroid-release:
	cd apps/android && ANDROID_HOME="$(ANDROID_HOME)" ./gradlew :app:assembleFdroidRelease
	cd apps/android && ANDROID_HOME="$(ANDROID_HOME)" ./scripts/verify-fdroid-artifact.sh

practice-build:
	cd apps/practice && npm run build

website-build:
	cd apps/website && npm run build
