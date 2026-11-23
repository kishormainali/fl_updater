# fl_updater_firebase

Firebase Remote Config provider for [`fl_updater`](../fl_updater).

```dart
FlUpdaterWrapper(
  provider: FirebaseConfigProvider(),
  child: child!,
)
```

Publish the update config as the `fl_updater_config` Remote Config parameter
(JSON schema documented in `fl_updater`). Real-time updates are supported.
