# fl_updater_firebase

Firebase Remote Config provider for [`fl_updater`](https://pub.dev/packages/fl_updater).

```yaml
dependencies:
  fl_updater: ^0.2.0
  fl_updater_firebase: ^0.2.0
  firebase_core: ^4.13.0 # or latest
```

```dart
await Firebase.initializeApp();

FlUpdaterWrapper(
  provider: FirebaseConfigProvider(),
  child: child!,
)
```

- Publish the update config as the `fl_updater_config` Remote Config parameter
  (JSON schema and console setup: see the `fl_updater` README).
- `fetch` honours `minimumFetchInterval` (default 1 hour) and activates fetched values.
- Real-time updates are supported (`changes` is backed by `onConfigUpdated`); a
  publish activates the new config and re-evaluates immediately.
- Pass your own `FirebaseRemoteConfig` via `FirebaseConfigProvider(remoteConfig: ...)`
  if you need a non-default instance.
