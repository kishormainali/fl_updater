# Changelog

## 0.1.0

### Breaking Changes

* **Replaced the two flat Remote Config parameters with a single JSON-structured one.** `fl_updater_latest_version` and `fl_updater_min_version` are gone; `fl_updater` now reads one String parameter, `fl_updater_config`, whose value is a JSON object: `{"latest_version": "1.0.0", "min_version": "1.0.0"}`.
  * `UpdateInfo.fromRemoteConfigValues` is replaced by `UpdateInfo.fromRemoteConfigJson`, which parses this JSON directly instead of taking a `Map<String, String>`.
  * `UpdateInfo.fromTemplateJson` drops its old `platform` parameter (a `TargetPlatform` used for Remote Config condition-based lookup of the old parameter names) in favor of a `String? platform` matching the new JSON schema's `platforms` key, and now reads the `fl_updater_config` parameter's default value using that schema.
* Renamed `enableInDebugMode` to `enabled` on `FlUpdaterWrapper`, `FlUpdater.checkForUpdate`, `FlUpdater.showUpdateDialog`, and `RemoteConfigService.checkForUpdate`.
  * `enabled` is now the single global gate for *all* automatic update behavior — the initial check, real-time listening, and `clearSnoozeInDebugMode` — checked first and taking precedence over every other flag.
  * Defaults to `!kDebugMode`, matching the previous default behavior (checks skipped in debug, run in release). Unlike the old flag, `enabled` can now also fully disable checking in release builds, not just opt into it in debug.
  * Toggling `enabled` at runtime (e.g. via a rebuild) now dynamically tears down or re-establishes the real-time Remote Config listener.
* Raised the minimum supported SDK to Dart `>=3.4.0` and Flutter `>=3.24.0` (previously `>=3.0.0` / `>=3.10.0`), required by the new `fp_logger` dependency (see Improvements).
* Removed the exported `FlUpdaterLogger` class. Diagnostic logging is now emitted directly via `fp_logger`'s `Logger`; `FlUpdater.enableLogging` and every `enableLogging` parameter are unaffected.

### Features

* **Per-Flavor and Per-Platform Remote Config Targeting**: Support for multiple apps registered under the same Firebase project (one per build flavor), and/or different version numbers per platform, from a single `fl_updater_config` parameter. Nest optional `flavors` (keyed by flavor name, e.g. `development`, `staging`, `uat`, `production`) and/or `platforms` (keyed by `android` / `ios`, each of which can itself nest its own `flavors`) objects in the JSON. `RemoteConfigService.checkForUpdate`/`evaluateActiveConfig`, `FlUpdater.checkForUpdate`/`showUpdateDialog`, and `FlUpdaterWrapper` now accept `flavor` and `platform` parameters (defaulting to Flutter's built-in `appFlavor` and the detected platform respectively, so most apps need no code change). Every object and field is optional — `latest_version` and `min_version` are each resolved independently, most specific first: `platforms.<platform>.flavors.<flavor>`, then `platforms.<platform>`, then `flavors.<flavor>`, then the top-level field.

### Fixes

* `VersionComparator` now correctly parses versions with a build-number suffix in `x.x.x+x` form (e.g. `1.0.0+10`, matching `pubspec.yaml`'s `version:` field convention). Previously the `+build` suffix corrupted the patch segment's parse (silently falling back to `0`); it's now parsed as its own trailing precedence tier, compared only once every semantic segment (major/minor/patch) is equal.
* Fixed `RemoteConfigService` reading the installed version from `PackageInfo.version` alone, which never includes the build number. Any `min_version`/`latest_version` configured with a `+BUILD` suffix therefore always compared as newer than the installed build, showing the non-dismissible force-update dialog on every launch even when the installed build already satisfied `min_version`. The installed build number is now appended (`x.x.x+x`) before comparison.
* Fixed a crash — `The context used to push or pop routes from the Navigator must be that of a widget that is a descendant of a Navigator widget` — that could occur when `FlUpdaterWrapper` presented its update dialog in apps where the wrapper wasn't a strict ancestor of the app's `Navigator`. The Navigator lookup now also searches from the app's root element and always resolves to a genuine Navigator-descendant context.
* Fixed the Android module requiring a very recent Gradle/AGP/Kotlin toolchain (`Minimum supported Gradle version is 9.3.1`), which broke builds on older but still current Gradle installs. Lowered the pinned Android Gradle Plugin and Kotlin versions and made Kotlin plugin application AGP-version-aware, so the module now builds correctly across both older and newer Android toolchains.

### Improvements

* Trimmed diagnostic logging (`enableLogging: true`) to fewer, denser lines — removed redundant/duplicate log lines and consolidated multi-line status output (current version, fetched config, evaluated status) into a single line per check.
* Replaced the hand-rolled `debugPrint`/`dev.log` logging with [`fp_logger`](https://pub.dev/packages/fp_logger), giving diagnostic logs (`enableLogging: true`) formatted, colorized console output.
* The fetched `fl_updater_config` JSON is now logged pretty-printed (indented, multi-line) on its own, instead of dumped inline as one unreadable minified blob in the status summary line.

## 0.0.2

Release of `fl_updater`, a lightweight, cost-conscious Flutter plugin for Firebase Remote Config-driven app updates.

### Features

* **Automatic Update Wrapper (`FlUpdaterWrapper`)**: Check and present update dialogs seamlessly upon app launch via `MaterialApp.builder` with automatic `Navigator` resolution and custom `navigatorKey` support.
* **Programmatic API (`FlUpdater`)**: Check for updates (`checkForUpdate`) and present update dialogs (`showUpdateDialog`) imperatively.
* **Remote Config Integration**:
  * Evaluates `fl_updater_latest_version` and `fl_updater_min_version` parameters.
  * Supports platform-specific targeting using Firebase Remote Config conditions (`fl_updater_android` and `fl_updater_ios`).
  * Offline / template JSON parsing support via `UpdateInfo.fromTemplateJson`.
* **Two-Tier Update System**:
  * **Soft updates**: Optional update prompt with a "Later" button.
  * **Force updates**: Mandatory blocking dialog (`canPop: false`) when the installed version is below `fl_updater_min_version`.
* **Smart Snoozing**:
  * Snooze soft updates for a customizable duration (default: 3 days), scoped per version.
  * `clearSnoozeInDebugMode` flag on `FlUpdaterWrapper` to automatically clear saved snooze state on launch in debug mode.
  * Programmatic snooze reset methods: `FlUpdater.clearSnoozeStore()` and `FlUpdater().clearSnooze()`.
* **Real-Time Remote Config Updates**:
  * Real-time listeners (`FirebaseRemoteConfig.onConfigUpdated`) automatically activate published changes to `fl_updater_latest_version` and `fl_updater_min_version` instantly without waiting for `minimumFetchInterval`.
  * Enabled by default with `listenForRealtimeUpdates: true` on `FlUpdaterWrapper`.
* **Cost-Conscious Fetching & Quota Optimization**:
  * Disabled in `kDebugMode` by default to prevent burning Remote Config fetch quotas during development and hot reloads.
  * Configurable `minimumFetchInterval` (default: 1 hour) caching.
* **Diagnostic Logging**:
  * Built-in `FlUpdaterLogger` utility with global and local `enableLogging` toggles.
* **Native Store Integration**:
  * Native redirection to the Apple App Store (via numeric `iosAppId`) and Google Play Store (via `androidPackageId`).
* **Extensible UI & Styling**:
  * Customizable dialog appearance using `FlUpdaterDialogStyle`.
  * Complete UI override using custom `dialogBuilder` (`FlUpdaterDialogBuilder`).

## 0.0.1

Initial release of `fl_updater`, a lightweight, cost-conscious Flutter plugin for Firebase Remote Config-driven app updates.