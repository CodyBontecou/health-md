## Health.md monorepo command router

ANDROID_HOME ?= $(HOME)/Library/Android/sdk
CORE_RUST_DIR := packages/healthmd-core-rust
TEST_JOBS ?= 4
ANDROID_TEST_ARGS ?= --max-workers=2 --init-script scripts/ci-gradle.init.gradle
APPLE_TEST_DERIVED_DATA_DIR ?= $(CURDIR)/apps/apple/build/local-test-derived-data
CORE_BINDINGS_DIR ?= $(CURDIR)/$(CORE_RUST_DIR)/target/generated-bindings

.PHONY: test test-components test-contracts test-product-parity test-core check-core-registry core-bindings check-core-bindings \
        test-apple test-android test-cli test-practice test-wake test-website apple-ios apple-macos cli-build \
        android-build android-play-debug android-fdroid-debug android-fdroid-release \
        practice-build website-build

# Bound component concurrency, preserve every gate, and report all failures.
# TEST_JOBS=1 retains serial scheduling for diagnosis or smaller machines.
test:
	$(MAKE) --jobs="$(TEST_JOBS)" --keep-going test-components

test-components: test-contracts test-core test-apple test-android test-cli test-practice test-wake test-website

test-contracts:
	python3 packages/contracts/validate.py

test-product-parity:
	python3 packages/contracts/validate.py --product-parity-only

test-core: check-core-registry
	cd $(CORE_RUST_DIR) && cargo test --workspace --all-features --locked

check-core-registry:
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
	$(MAKE) -C apps/apple test \
	  IOS_DERIVED_DATA_DIR="$(APPLE_TEST_DERIVED_DATA_DIR)/ios" \
	  MACOS_DERIVED_DATA_DIR="$(APPLE_TEST_DERIVED_DATA_DIR)/macos"

test-android:
	cd apps/android && ANDROID_HOME="$(ANDROID_HOME)" ./gradlew test $(ANDROID_TEST_ARGS)

test-cli:
	cd apps/cli && cargo test --workspace --all-features

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
