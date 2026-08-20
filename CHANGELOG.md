## 0.1.0

### Breaking Changes
* Renamed `enableInDebugMode` to `enabled` on `FlUpdaterWrapper`, `FlUpdater.checkForUpdate`, `FlUpdater.showUpdateDialog`, and `RemoteConfigService.checkForUpdate`.
  * `enabled` is now the single global gate for *all* automatic update behavior — the initial check, real-time listening, and `clearSnoozeInDebugMode` — checked first and taking precedence over every other flag.
  * Defaults to `!kDebugMode`, matching the previous default behavior (checks skipped in debug, run in release). Unlike the old flag, `enabled` can now also fully disable checking in release builds, not just opt into it in debug.
  * Toggling `enabled` at runtime (e.g. via a rebuild) now dynamically tears down or re-establishes the real-time Remote Config listener.

### Fixes
* Fixed a crash — `The context used to push or pop routes from the Navigator must be that of a widget that is a descendant of a Navigator widget` — that could occur when `FlUpdaterWrapper` presented its update dialog in apps where the wrapper wasn't a strict ancestor of the app's `Navigator`. The Navigator lookup now also searches from the app's root element and always resolves to a genuine Navigator-descendant context.
* Fixed the Android module requiring a very recent Gradle/AGP/Kotlin toolchain (`Minimum supported Gradle version is 9.3.1`), which broke builds on older but still current Gradle installs. Lowered the pinned Android Gradle Plugin and Kotlin versions and made Kotlin plugin application AGP-version-aware, so the module now builds correctly across both older and newer Android toolchains.

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