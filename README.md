# fl_updater

[![pub package](https://img.shields.io/pub/v/fl_updater.svg)](https://pub.dev/packages/fl_updater)
[![pub points](https://img.shields.io/pub/points/fl_updater?color=2E8B57)](https://pub.dev/packages/fl_updater/score)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A lightweight, cost-conscious Flutter plugin for **Firebase Remote Config-driven app updates**. Supports automatic launch checks, soft updates with per-version snoozing, non-dismissible force updates, and native App Store / Google Play Store redirection.

---

## ✨ Features

- 🚀 **Declarative Wrapper**: Wrap your `MaterialApp` with `FlUpdaterWrapper` for zero-boilerplate launch checks.
- ⚡ **Imperative API**: Use `FlUpdater().checkForUpdate()` or `FlUpdater().showUpdateDialog()` for manual checks (e.g. from a settings screen).
- 🔄 **Soft & Force Updates**:
  - **Soft updates**: Optional update prompt with a "Later" button.
  - **Force updates**: Mandatory blocking dialog (`canPop: false`) when the installed version is below `min_version`.
- ⏰ **Smart Snoozing**: Dismissing a soft update snoozes it for a configurable duration (default: 3 days). Snooze is scoped per version, so releasing a newer update immediately prompts the user again.
- 💰 **Cost-Conscious Architecture**: Designed for Firebase Remote Config usage-based pricing:
  - **Debug mode disabled by default**: Prevents development hot restarts from consuming Remote Config quotas.
  - **Cached fetches**: Configurable `minimumFetchInterval` (default: 1 hour) ensures throttled network requests.
- 🏬 **Native Store Redirection**: Opens the platform's native store page (Apple App Store on iOS, Google Play Store on Android).
- 🎨 **Fully Customizable UI**: Style the built-in Material dialog with `FlUpdaterDialogStyle`, or supply your own custom UI via `dialogBuilder`.

---

## 📦 Installation

Add `fl_updater` and `firebase_core` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  fl_updater: ^0.0.1
  firebase_core: ^4.13.0 # or latest
```

Then ensure Firebase is initialized in your `main()` method:

```dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}
```

---

## 🔧 Firebase Remote Config Setup

`fl_updater` reads a single JSON-structured String parameter, `fl_updater_config`, from **Firebase Console → Build → Remote Config**. This section walks through setting it up from scratch, plus optional platform- and flavor-targeting layers.

> In-app update prompts only make sense for the build that's actually published to the App Store / Play Store — a dev/staging/internal build isn't distributed there, so there's nothing for it to "update" to. This guide is written with that in mind: one Firebase project, one production app. If you register multiple apps (one per build flavor) under the same Firebase project, see "Step 2 — (Optional) Different values per flavor and/or platform" below for targeting a specific one.

### Step 1 — Create the parameter

Go to **Build → Remote Config**. If this is the project's first Remote Config parameter, click **Create configuration**; otherwise click **Add parameter**.

Create a String parameter named `fl_updater_config` with a JSON object as its default value:

```json
{
  "latest_version": "1.0.0",
  "min_version": "1.0.0"
}
```

- `latest_version`: the latest published version available in stores.
- `min_version`: the minimum supported version. Installs below this get a non-dismissible force update.

Both accept plain semantic versions (`1.0.0`) or a version with a build-number suffix (`1.0.0+10`, matching `pubspec.yaml`'s `version:` field) — the build number is compared too whenever the semantic version alone is a tie.

Click **Publish changes**. At this point every install of your app sees the same JSON value — no targeting yet.

### Step 2 — (Optional) Different values per flavor and/or platform

Skip this step if every install should see the same version numbers.

Nest `flavors` and/or `platforms` objects inside `fl_updater_config` — no separate Remote Config condition needed:

```json
{
  "latest_version": "1.0.0",
  "min_version": "1.0.0",
  "flavors": {
    "development": { "latest_version": "1.2.0", "min_version": "1.0.0" },
    "staging": { "latest_version": "1.1.0", "min_version": "1.0.0" },
    "uat": { "latest_version": "1.1.0", "min_version": "1.0.0" },
    "production": { "latest_version": "1.0.0", "min_version": "1.0.0" }
  },
  "platforms": {
    "android": {
      "latest_version": "1.0.1",
      "min_version": "1.0.0",
      "flavors": {
        "development": { "latest_version": "1.2.1", "min_version": "1.0.0" }
      }
    },
    "ios": {
      "latest_version": "1.0.0",
      "min_version": "1.0.0"
    }
  }
}
```

- **`flavors`**: for apps registered per build flavor under the same Firebase project (`development`, `staging`, `uat`, `production`, ...), each with its own `google-services.json` / `GoogleService-Info.plist`.
- **`platforms`**: for different version numbers per platform (`android` / `ios`) — an alternative to Remote Config conditions that lives entirely in this one parameter. Each platform entry can itself nest its own `flavors` object.

Every one of these objects, and every field within them, is optional — set only what actually diverges from the shared default. `latest_version` and `min_version` are each resolved **independently**, most specific first:

1. `platforms.<platform>.flavors.<flavor>.<field>`
2. `platforms.<platform>.<field>`
3. `flavors.<flavor>.<field>`
4. the top-level `<field>`

Publish changes once you've added the values you need.

In code, `fl_updater` reads the flavor and platform automatically — flavor from Flutter's built-in `appFlavor` (the value passed to `flutter run/build --flavor <name>`), platform from the running device — so nothing needs to be configured. Pass `flavor:` / `platform:` explicitly to `FlUpdaterWrapper` / the imperative API only if you want to override either.

### Step 3 — Configure store redirection identifiers (in code, not console)

Not part of Remote Config — pass these directly to `FlUpdaterWrapper` / the imperative API:

- **iOS (`iosAppId`)**: Numeric Apple App Store ID (e.g., `'123456789'`).
- **Android (`androidPackageId`)**: Package name (e.g., `'com.example.app'`). Defaults to the host app package name if omitted.

### Step 4 — Verify it worked

- Run the app with `enableLogging: true` (see "🪵 Diagnostic Logging" below) and look for the `Fetched remote config value (fl_updater_config): {...}` log line to confirm the JSON `fl_updater` actually received.
- Pass `enabled: true` while testing — it defaults to `!kDebugMode`, so debug builds skip fetching entirely otherwise (see "💰 Fetch Behavior & Quota Optimization" below).
- Remote Config itself throttles fetches via `minimumFetchInterval` (default 1 hour) — repeated test runs within that window reuse the previous fetch. Lower it temporarily while iterating if a fresh publish doesn't seem to take effect.

---

## 🚀 Usage

### 1. Automatic Usage (Recommended)

Wrap your `MaterialApp` with `FlUpdaterWrapper` inside the `builder` callback:

```dart
import 'package:flutter/material.dart';
import 'package:fl_updater/fl_updater.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) => FlUpdaterWrapper(
        iosAppId: '123456789',
        androidPackageId: 'com.example.app', // Optional: defaults to host package
        child: child!,
      ),
      home: const HomePage(),
    );
  }
}
```

This checks Remote Config once when the app is launched and displays the update dialog if an update is available and not currently snoozed.

---

### 2. Imperative / Manual Usage

Trigger an update check manually, such as from an "About" or "Settings" screen:

```dart
final updater = FlUpdater();

// Check and show dialog if an update is available:
await updater.showUpdateDialog(
  context,
  iosAppId: '123456789',
  androidPackageId: 'com.example.app',
);
```

Or check status without displaying a UI:

```dart
final updater = FlUpdater();
final info = await updater.checkForUpdate(
  iosAppId: '123456789',
);

print('Current: ${info.currentVersion}');
print('Latest: ${info.latestVersion}');
print('Status: ${info.status}'); // UpdateStatus.none, soft, or force
```

---

## 🎨 Customization

### Styling the Default Dialog

Customize colors, typography, buttons, shapes, and icons using `FlUpdaterDialogStyle`:

```dart
FlUpdaterWrapper(
  iosAppId: '123456789',
  title: 'Exciting New Update!',
  message: 'We added new features and performance improvements.',
  updateButtonText: 'Update Now',
  laterButtonText: 'Not Now',
  style: FlUpdaterDialogStyle(
    backgroundColor: Colors.white,
    titleStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
    messageStyle: const TextStyle(color: Colors.black87),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    icon: const Icon(Icons.system_update, size: 40, color: Colors.blue),
  ),
  child: child!,
)
```

### Providing a Custom Update UI (`dialogBuilder`)

Replace the built-in dialog entirely with your own custom widget or bottom sheet:

```dart
FlUpdaterWrapper(
  iosAppId: '123456789',
  dialogBuilder: (context, info, onUpdate, onLater) {
    final isForce = info.status == UpdateStatus.force;
    return AlertDialog(
      title: Text('Version ${info.latestVersion} Available'),
      content: Text('You are on ${info.currentVersion}. Please update to continue.'),
      actions: [
        if (!isForce)
          TextButton(
            onPressed: onLater, // Snoozes the update and dismisses dialog
            child: const Text('Remind me later'),
          ),
        ElevatedButton(
          onPressed: onUpdate, // Redirects to App/Play Store
          child: const Text('Update'),
        ),
      ],
    );
  },
  child: child!,
)
```

---

## ⏰ Snoozing Behavior

When a **soft (optional)** update is available, tapping the "Later" button snoozes update prompts for `snoozeDuration` (default: 3 days).

- The snooze is persisted locally via `SharedPreferences`.
- Snoozes are **scoped to the latest version**. When you publish a newer version in Remote Config, the active snooze is automatically invalidated.
- **Force updates** always bypass snooze and cannot be dismissed.

```dart
FlUpdaterWrapper(
  snoozeDuration: const Duration(days: 7), // Snooze for 1 week
  child: child!,
)
```

### Resetting Snooze (For Debugging & Testing)

You can automatically clear the snooze store on every app launch during development:

```dart
FlUpdaterWrapper(
  enabled: true,
  clearSnoozeInDebugMode: true, // Clears previous snoozes on app launch in debug mode
  child: child!,
)
```

Or reset it manually via code:

```dart
// Globally clear active snooze state:
await FlUpdater.clearSnoozeStore();

// Or on an instance:
final updater = FlUpdater();
await updater.clearSnooze();
```

---

## 💰 Fetch Behavior & Quota Optimization

To safeguard your Firebase Remote Config quota and avoid unintended billing:

1. **Disabled in Debug Mode by Default**: `enabled` defaults to `!kDebugMode`, so Remote Config fetching is skipped entirely in debug builds and frequent hot restarts do not burn quotas. `enabled` is the global gate for both the initial check and real-time listening — pass it explicitly to override the default in either direction:
   ```dart
   FlUpdaterWrapper(
     enabled: true, // Opt-in for debug/staging builds
     child: child!,
   )
   ```
2. **Fetch Interval Throttling**: The `minimumFetchInterval` (default: 1 hour) prevents frequent network queries. Repeated checks within this duration use the Firebase cached values.
   ```dart
   FlUpdaterWrapper(
     minimumFetchInterval: const Duration(minutes: 30),
     child: child!,
   )
   ```

---

## ⚡ Real-Time Remote Config Updates

`fl_updater` listens to Firebase Remote Config updates in real time via `onConfigUpdated`:

- When you publish changes to `fl_updater_config` in the Firebase Console, the new config is activated **immediately**.
- The update status is evaluated without waiting for `minimumFetchInterval` to expire.
- Active snoozes are automatically cleared so users are prompted for the newly published version right away.
- If the new version requires an update, the update dialog appears instantly for active users.

Real-time updates are enabled by default (`listenForRealtimeUpdates: true`). You can disable them if needed:

```dart
FlUpdaterWrapper(
  listenForRealtimeUpdates: false, // Only check on app launch
  child: child!,
)
```

---

## 🪵 Diagnostic Logging

Logging is **disabled by default** to keep console and production outputs clean. You can enable diagnostic logging in several ways:

### 1. Globally

```dart
void main() {
  FlUpdater.enableLogging = true;
  runApp(const MyApp());
}
```

### 2. Per Wrapper or Method Call

```dart
FlUpdaterWrapper(
  enableLogging: true,
  child: child!,
)
```

---

## 📖 API Reference

### `FlUpdaterWrapper` & `FlUpdater.showUpdateDialog`

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `iosAppId` | `String?` | `null` | Numeric Apple App Store ID (required for iOS). |
| `androidPackageId` | `String?` | `null` | Google Play Store package name (defaults to host app). |
| `navigatorKey` | `GlobalKey<NavigatorState>?` | `null` | Optional explicit key for the root `Navigator`. |
| `snoozeDuration` | `Duration` | `Duration(days: 3)` | How long to snooze soft updates when dismissed. |
| `minimumFetchInterval` | `Duration` | `Duration(hours: 1)` | Throttling interval for Firebase Remote Config fetches. |
| `enabled` | `bool` | `!kDebugMode` | Global gate for automatic update checking (initial check and real-time listening). |
| `clearSnoozeInDebugMode` | `bool` | `false` | Automatically clear saved snooze state on launch in debug mode. |
| `listenForRealtimeUpdates` | `bool` | `true` | Instantly activate and check updates on Remote Config publish. |
| `enableLogging` | `bool?` | `null` | Enable diagnostic console logs for troubleshooting. |
| `title` | `String?` | `'Update available'` | Dialog title text. |
| `message` | `String?` | `null` | Dialog message body text. |
| `updateButtonText` | `String?` | `'Update'` | Label for the update button. |
| `laterButtonText` | `String?` | `'Later'` | Label for the later/snooze button. |
| `style` | `FlUpdaterDialogStyle?` | `null` | Style configuration for the default dialog. |
| `dialogBuilder` | `FlUpdaterDialogBuilder?` | `null` | Custom builder to provide your own dialog UI. |

---

## 📱 Example App

Check out the [example](https://github.com/kishormainali/fl_updater/tree/main/example) directory for a complete sample app demonstrating both automatic wrapper and manual checking with Firebase Remote Config.

To run the example app:

```bash
cd example
flutter run
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
