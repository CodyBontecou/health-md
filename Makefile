## Health.md monorepo command router

.PHONY: test test-apple test-android test-cli test-website \
        apple-ios apple-macos cli-build android-build website-build

test: test-apple test-android test-cli test-website

test-apple:
	$(MAKE) -C apps/apple test

test-android:
	cd apps/android && ./gradlew test

test-cli:
	cd apps/cli && cargo test --workspace --all-features

test-website:
	cd apps/website && npm test

apple-ios:
	$(MAKE) -C apps/apple test-ios

apple-macos:
	$(MAKE) -C apps/apple test-macos

cli-build:
	cd apps/cli && cargo build --workspace

android-build:
	cd apps/android && ./gradlew assembleDebug

website-build:
	cd apps/website && npm run build
