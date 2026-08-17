## 0.0.1

Initial release of `fl_updater`, a lightweight, cost-conscious Flutter plugin for Firebase Remote Config-driven app updates.

### Features
* **Automatic update wrapper (`FlUpdaterWrapper`)**: Check and present update dialogs seamlessly upon app launch via `MaterialApp.builder`.
* **Programmatic API (`FlUpdater`)**: Check for updates (`checkForUpdate`) and present dialogs (`showUpdateDialog`) imperatively.
* **Two-tier update system**:
  * **Soft updates**: Optional update prompt with a "Later" button.
  * **Force updates**: Mandatory, non-dismissible prompt for builds below `fl_updater_min_version`.
* **Smart snoozing**: Snooze soft updates for a customizable duration (default: 3 days), scoped per version.
* **Cost-conscious Remote Config fetching**:
  * Disabled in `kDebugMode` by default to prevent burning fetch quotas during development and hot reloads.
  * Throttled with `minimumFetchInterval` (default: 12 hours) caching.
* **Native Store integration**: Direct store opening for Android (Google Play Store) and iOS (Apple App Store).
* **Extensible UI & styling**:
  * Customizable dialog appearance using `FlUpdaterDialogStyle`.
  * Complete UI override using `dialogBuilder` (`FlUpdaterDialogBuilder`).
