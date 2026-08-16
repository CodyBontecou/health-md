## Health.md monorepo command router

ANDROID_HOME ?= $(HOME)/Library/Android/sdk
CORE_RUST_DIR := packages/healthmd-core-rust
CORE_BINDINGS_DIR ?= $(CURDIR)/$(CORE_RUST_DIR)/target/generated-bindings

.PHONY: test test-contracts test-product-parity test-core check-core-registry core-bindings check-core-bindings \
        test-apple test-android test-cli test-website test-pi-health-dashboard apple-ios apple-macos cli-build \
        android-build website-build

test: test-contracts test-core test-apple test-android test-cli test-website test-pi-health-dashboard

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
	$(MAKE) -C apps/apple test

test-android:
	cd apps/android && ANDROID_HOME="$(ANDROID_HOME)" ./gradlew test

test-cli:
	cd apps/cli && cargo test --workspace --all-features

test-website:
	cd apps/website && npm test

test-pi-health-dashboard:
	cd packages/pi-healthmd-dashboard && npm test && npm run typecheck

apple-ios:
	$(MAKE) -C apps/apple test-ios

apple-macos:
	$(MAKE) -C apps/apple test-macos

cli-build:
	cd apps/cli && cargo build --workspace

android-build:
	cd apps/android && ANDROID_HOME="$(ANDROID_HOME)" ./gradlew assembleDebug

website-build:
	cd apps/website && npm run build
