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