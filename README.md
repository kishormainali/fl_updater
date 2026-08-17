# fl_updater

A Flutter plugin that shows an app-update dialog driven by Firebase Remote
Config, and opens the platform's App Store / Play Store page natively.

## Remote Config keys

| Key | Type | Meaning |
| --- | --- | --- |
| `fl_updater_latest_version` | string | Latest published version, e.g. `"2.3.0"` |
| `fl_updater_min_version` | string | Versions below this trigger a blocking update. Defaults to `"0.0.0"` (never forces). |

That's the whole schema — nothing else lives in Remote Config. The App Store
id and Android package id are static per-app values, not something you'd
toggle from a dashboard, so they're passed directly instead:

```dart
FlUpdaterWrapper(
  iosAppId: '123456789',           // required on iOS — no on-device fallback
  androidPackageId: 'com.you.app', // optional — defaults to the host app's own package name
  child: child!,
)
```

## Automatic usage

```dart
MaterialApp(
  builder: (context, child) => FlUpdaterWrapper(
    iosAppId: '123456789',
    androidPackageId: 'com.you.app',
    child: child!,
  ),
  home: const HomePage(),
)
```

Checks once per app launch and shows the dialog automatically when an update
is available.

## Imperative usage

```dart
final updater = FlUpdater();
await updater.showUpdateDialog(
  context,
  iosAppId: '123456789',
  androidPackageId: 'com.you.app',
);
```

## Fetch behavior and cost

Remote Config moved to usage-based pricing on 2026-09-01, so `fl_updater`
is deliberately conservative about fetching:

- **Debug builds fetch nothing by default.** `kDebugMode` disables the
  Remote Config check entirely (no dialog, no network call) so hot restarts
  while developing don't burn fetches or pop up dialogs unannounced. Pass
  `enableInDebugMode: true` to opt back in — e.g. in your own debug/staging
  build of the example app.
- **`minimumFetchInterval`** (default 12 hours, matching the Firebase SDK's
  own default) caps how often a real fetch happens even in release builds;
  repeated checks inside that window are served from the SDK's cache.

```dart
FlUpdaterWrapper(
  minimumFetchInterval: const Duration(days: 1),
  child: child!,
)
```

## Customization

Style the built-in dialog:

```dart
FlUpdaterWrapper(
  style: FlUpdaterDialogStyle(
    titleStyle: TextStyle(fontWeight: FontWeight.bold),
  ),
  title: 'New version available',
  child: child!,
)
```

Or replace it entirely:

```dart
FlUpdaterWrapper(
  dialogBuilder: (context, info, onUpdate, onLater) {
    return MyCustomUpdateSheet(info: info, onUpdate: onUpdate, onLater: onLater);
  },
  child: child!,
)
```

## Snoozing

Tapping "Later" on a soft (non-forced) update snoozes it for `snoozeDuration`
(default 3 days), per version — publishing a newer `fl_updater_latest_version`
immediately invalidates an active snooze.

```dart
FlUpdaterWrapper(
  snoozeDuration: const Duration(days: 7),
  child: child!,
)
```

Force updates (installed version below `fl_updater_min_version`) always
ignore snooze and cannot be dismissed.
