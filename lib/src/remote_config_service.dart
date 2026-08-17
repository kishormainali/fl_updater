import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'models/update_info.model.dart';
import 'models/update_status.dart';
import 'snooze_store.dart';

class RemoteConfigService {
  RemoteConfigService({FirebaseRemoteConfig? remoteConfig, FlUpdaterSnoozeStore? snoozeStore})
      : _providedRemoteConfig = remoteConfig,
        _snoozeStore = snoozeStore ?? FlUpdaterSnoozeStore();

  // Resolved lazily via the getter below so constructing a RemoteConfigService
  // never touches FirebaseRemoteConfig.instance until a check actually needs
  // it — that's what keeps the debug-mode-gated tests above free of any
  // Firebase test setup.
  final FirebaseRemoteConfig? _providedRemoteConfig;
  final FlUpdaterSnoozeStore _snoozeStore;

  FirebaseRemoteConfig get _remoteConfig => _providedRemoteConfig ?? FirebaseRemoteConfig.instance;

  static const _keys = [
    'fl_updater_latest_version',
    'fl_updater_min_version',
  ];

  Future<UpdateInfo> checkForUpdate({
    Duration snoozeDuration = const Duration(days: 3),
    Duration minimumFetchInterval = const Duration(hours: 12),
    bool enableInDebugMode = false,
    String? iosAppId,
    String? androidPackageId,
  }) async {
    if (kDebugMode && !enableInDebugMode) {
      return UpdateInfo(
        currentVersion: '',
        latestVersion: '',
        status: UpdateStatus.none,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    try {
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(minutes: 1),
          minimumFetchInterval: minimumFetchInterval,
        ),
      );
      await _remoteConfig.setDefaults({for (final key in _keys) key: ''});
      await _remoteConfig.fetchAndActivate();

      final values = {for (final key in _keys) key: _remoteConfig.getString(key)};

      var info = UpdateInfo.fromRemoteConfigValues(
        values: values,
        currentVersion: currentVersion,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );

      if (info.status == UpdateStatus.soft && await _snoozeStore.isSnoozed(info.latestVersion)) {
        info = info.copyWith(status: UpdateStatus.none);
      }

      return info;
    } catch (error, stackTrace) {
      debugPrint('fl_updater: failed to fetch remote config: $error\n$stackTrace');
      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        status: UpdateStatus.none,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );
    }
  }
}
