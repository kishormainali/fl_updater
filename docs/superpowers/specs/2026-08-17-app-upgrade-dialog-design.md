# fl_updater: App Upgrade Dialog — Design

**Date:** 2026-08-17
**Status:** Approved

## Problem

`fl_updater` is a Flutter plugin scaffold (`flutter create --template=plugin`) with almost no real implementation: the Dart public API is an empty class, the platform interface has two unimplemented method stubs, the Android/iOS native sides still handle the default `getPlatformVersion` template method, and `lib/src/models/remote_config.model.dart` is not valid Dart (constructor parameters written directly as the class body).

The goal is to turn this into a working plugin that:
1. Reads app-update configuration from Firebase Remote Config.
2. Decides whether an update is available, and whether it must be forced (blocking) or is optional (dismissible).
3. Shows a built-in dialog to the user.
4. On tap, opens the correct app store page for the current platform using native APIs (not a generic browser URL).

## Non-goals

- No custom exception hierarchy or retry/backoff logic for Remote Config fetch — fail open and log.
- No Remote-Config-driven dialog copy — copy is a Dart-side API concern (see below).
- No `url_launcher` dependency — store opening is implemented directly via native platform channel code.
- No analytics/telemetry hooks in v1.

## Architecture

Four layers, following the existing plugin scaffold's structure:

1. **Remote Config service** (`lib/src/remote_config_service.dart`)
   Wraps `firebase_remote_config`: sets defaults, calls `fetchAndActivate()`, reads the flat keys described below, and produces an `UpdateInfo`.

2. **Version comparison** (`lib/src/version_comparator.dart`)
   Uses `package_info_plus` to get the installed version, and compares it against `latest_version` / `min_version` from Remote Config using semantic-version rules. Produces an `UpdateStatus` enum: `none`, `soft` (update available, dismissible), `force` (installed version is below `min_version`, blocking).

3. **Dialog widget** (`lib/src/update_dialog.dart`)
   An adaptive `AlertDialog`.
   - Force mode: `PopScope(canPop: false)`, `barrierDismissible: false`, no "Later" button — only path forward is tapping "Update".
   - Soft mode: adds a "Later" button that just pops the dialog; the app is expected to re-check on next launch/resume (no persistent "don't ask again" storage in v1).
   - Title, message, update-button text, and later-button text are optional parameters with sensible English defaults.

4. **Store launcher** (platform channel — replaces the current `openAppStore` / `openGooglePlayStore` stubs)
   - Android (Kotlin): opens `market://details?id=<package>` via an explicit `Intent` targeting the Play Store app; if that fails (`ActivityNotFoundException`, Play Store app not installed), falls back to `https://play.google.com/store/apps/details?id=<package>` via `ACTION_VIEW`.
   - iOS (Swift): opens `itms-apps://itunes.apple.com/app/id<appId>` via `UIApplication.shared.open(...)`; if `canOpenURL` returns false, falls back to `https://apps.apple.com/app/id<appId>`.
   - Package/app id defaults to the host app's own identifiers, overridable via Remote Config keys.

## Public Dart API

Replaces the empty `FlUpdater` class in `lib/fl_updater.dart`:

```dart
class FlUpdater {
  Future<UpdateInfo> checkForUpdate();

  Future<void> showUpdateDialog(
    BuildContext context, {
    UpdateInfo? info, // if omitted, calls checkForUpdate() internally
    String? title,
    String? message,
    String? updateButtonText,
    String? laterButtonText,
  });
}
```

`UpdateInfo` (replacing/fixing `lib/src/models/remote_config.model.dart`, renamed `lib/src/models/update_info.model.dart`):

```dart
enum UpdateStatus { none, soft, force }

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final UpdateStatus status;
  final String? iosAppId;
  final String? androidPackageId;

  const UpdateInfo({...});

  factory UpdateInfo.fromRemoteConfigValues(...);

  @override
  int get hashCode => ...;
  @override
  bool operator ==(Object other) => ...;
  @override
  String toString() => ...;
}
```

## Remote Config schema (flat keys)

- `fl_updater_latest_version` (string, e.g. `"2.3.0"`)
- `fl_updater_min_version` (string) — installed version below this ⇒ `UpdateStatus.force`
- `fl_updater_ios_app_id` (string, numeric App Store id)
- `fl_updater_android_package_id` (string, optional — defaults to the host app's own package name if unset)

All keys have safe defaults (`fl_updater_min_version` defaults to `"0.0.0"`, i.e. force update never triggers unless explicitly configured) so an app that hasn't configured Remote Config yet never breaks.

## Error handling

`checkForUpdate()` wraps the Remote Config fetch in try/catch:
- On failure (network error, Remote Config misconfigured), logs via `debugPrint` and returns an `UpdateInfo` with `status: UpdateStatus.none`. The plugin fails open — a Remote Config outage must never block a user from using the app.
- No custom exception type in v1; this may change if consumers need to distinguish "no update" from "check failed."

## Testing

- **Unit tests** (`test/`):
  - `VersionComparator`: equal versions, patch/minor/major differences, malformed version strings, boundary at exactly `min_version`.
  - `UpdateInfo`: parsing from raw Remote Config value maps, `==`/`hashCode` contract.
  - `MethodChannelFlUpdater`: mocked `MethodChannel` verifying correct method names/arguments are sent for store-opening calls (existing pattern in the scaffold's `test/` dir).
- **Manual verification** in `example/`:
  - Android emulator: trigger soft and force update states, confirm dialog behavior (dismissible vs. blocked, back button behavior) and that tapping "Update" opens the Play Store app (or browser fallback).
  - iOS simulator: same, confirming App Store app opens (or Safari fallback).

## Files touched

- `lib/fl_updater.dart` — implement public API
- `lib/src/fl_updater_platform_interface.dart` — already has `openAppStore`/`openGooglePlayStore`; may adjust signatures to pass package/app id
- `lib/src/fl_updater_method_channel.dart` — already wired; verify method names match native side
- `lib/src/remote_config_service.dart` — new
- `lib/src/version_comparator.dart` — new
- `lib/src/update_dialog.dart` — new
- `lib/src/models/update_info.model.dart` — replaces broken `remote_config.model.dart`
- `android/src/main/kotlin/com/kishormainali/fl_updater/FlUpdaterPlugin.kt` — implement store-opening intents
- `ios/fl_updater/Sources/fl_updater/FlUpdaterPlugin.swift` — implement store-opening URL handling
- `pubspec.yaml` — add `package_info_plus` dependency (already has `firebase_remote_config`)
- `example/lib/main.dart` — demo usage
- `test/` — unit tests as described above
