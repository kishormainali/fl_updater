# fl_updater workspace

Remote-config-driven Flutter app updates (soft/snoozable and force updates, native store redirection).

| Package | Purpose |
|---|---|
| [`packages/fl_updater`](packages/fl_updater) | Core: `FlUpdater`, `FlUpdaterWrapper`, `FlUpdaterConfigProvider`, `ApiConfigProvider` (fetch config from your own API) |
| [`packages/fl_updater_firebase`](packages/fl_updater_firebase) | `FirebaseConfigProvider` (Firebase Remote Config) |
| [`example`](example) | Sample app |

See the [core README](packages/fl_updater/README.md) for usage. Develop with `flutter pub get` at the root, then `flutter test` inside each package.
Releases: push a per-package tag (`fl_updater-vX.Y.Z` or `fl_updater_firebase-vX.Y.Z`); core must be published before a Firebase release that requires it.
