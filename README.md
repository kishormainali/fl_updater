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
  - **Force updates**: Mandatory blocking dialog (`canPop: false`) when the installed version is below `fl_updater_min_version`.
- ⏰ **Smart Snoozing**: Dismissing a soft update snoozes it for a configurable duration (default: 3 days). Snooze is scoped per version, so releasing a newer update immediately prompts the user again.
- 💰 **Cost-Conscious Architecture**: Designed for Firebase Remote Config usage-based pricing:
  - **Debug mode disabled by default**: Prevents development hot restarts from consuming Remote Config quotas.
  - **Cached fetches**: Configurable `minimumFetchInterval` (default: 12 hours) ensures throttled network requests.
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

Configure the following parameters in your **Firebase Console → Remote Config**:

| Key | Type | Description | Example |
| :--- | :--- | :--- | :--- |
| `fl_updater_latest_version` | String | The latest published version available in stores. | `"2.3.0"` |
| `fl_updater_min_version` | String | The minimum supported version. Versions below this trigger a **mandatory (force)** update. | `"2.0.0"` |

> **Note**: If `fl_updater_min_version` is omitted or empty, it defaults to `"0.0.0"` (soft updates only).

App Store ID and Android package name are configured directly in Dart code since they are static per-app values:

- **iOS (`iosAppId`)**: Numeric App Store ID (e.g., `'123456789'`). Required on iOS for App Store redirection.
- **Android (`androidPackageId`)**: Package name (e.g., `'com.example.app'`). Defaults to the host app's package name if omitted.

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

---

## 💰 Fetch Behavior & Quota Optimization

To safeguard your Firebase Remote Config quota and avoid unintended billing:

1. **Disabled in Debug Mode by Default**: `kDebugMode` disables Remote Config fetching entirely so that frequent hot restarts do not burn quotas. To test in debug mode or staging, pass `enableInDebugMode: true`:
   ```dart
   FlUpdaterWrapper(
     enableInDebugMode: true, // Opt-in for debug/staging builds
     child: child!,
   )
   ```
2. **Fetch Interval Throttling**: The `minimumFetchInterval` (default: 12 hours) prevents frequent network queries. Repeated checks within this duration use the Firebase cached values.
   ```dart
   FlUpdaterWrapper(
     minimumFetchInterval: const Duration(hours: 6),
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
| `snoozeDuration` | `Duration` | `Duration(days: 3)` | How long to snooze soft updates when dismissed. |
| `minimumFetchInterval` | `Duration` | `Duration(hours: 12)` | Throttling interval for Firebase Remote Config fetches. |
| `enableInDebugMode` | `bool` | `false` | Enable checks in `kDebugMode`. |
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
