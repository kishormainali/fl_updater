# fl_updater_example

Demonstrates how to integrate and use the `fl_updater` package in a Flutter application.

## Features Demonstrated

1. **Automatic Launch Check**: Wrapping `MaterialApp` with `FlUpdaterWrapper` to check Remote Config on application launch.
2. **Imperative Update Check**: Triggering update checks manually using `FlUpdater().checkForUpdate()`.
3. **Custom Dialog Styling**: Applying theme colors, custom icons, and typography using `FlUpdaterDialogStyle`.
4. **Custom Dialog Builder**: Building bespoke update UI using `dialogBuilder` (`FlUpdaterDialogBuilder`).

## Getting Started

### 1. Configure Firebase (Optional for testing)

The example app is configured to fail open gracefully if Firebase is not connected. To test with real Remote Config values:

1. Create a Firebase project in the [Firebase Console](https://console.firebase.google.com/).
2. Run the FlutterFire CLI from this `example` directory:
   ```bash
   flutterfire configure
   ```
3. Add the following Remote Config keys:
   - `fl_updater_latest_version`: e.g. `"2.0.0"`
   - `fl_updater_min_version`: e.g. `"1.5.0"` (or leave empty for soft updates)
4. Publish changes in the Firebase Remote Config console.

### 2. Run the Example

```bash
flutter run
```
