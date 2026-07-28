fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios info

```sh
[bundle exec] fastlane ios info
```

Show current iOS app info on App Store Connect

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload metadata only (iOS)

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload screenshots only (iOS)

### ios upload_all

```sh
[bundle exec] fastlane ios upload_all
```

Upload metadata + screenshots (iOS)

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Submit for review (iOS)

----


## Mac

### mac info

```sh
[bundle exec] fastlane mac info
```

Show current macOS app info on App Store Connect

### mac upload_metadata

```sh
[bundle exec] fastlane mac upload_metadata
```

Upload metadata only (macOS)

### mac upload_screenshots

```sh
[bundle exec] fastlane mac upload_screenshots
```

Upload screenshots only (macOS)

### mac upload_all

```sh
[bundle exec] fastlane mac upload_all
```

Upload metadata + screenshots (macOS)

### mac submit

```sh
[bundle exec] fastlane mac submit
```

Submit for review (macOS)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
