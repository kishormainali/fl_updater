import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/update_info.model.dart';
import '../models/update_status.dart';
import '../utils/logger.dart';
import 'snooze_store.dart';

class RemoteConfigService {
  RemoteConfigService({
    FirebaseRemoteConfig? remoteConfig,
    FlUpdaterSnoozeStore? snoozeStore,
    this.enableLogging,
  })  : _providedRemoteConfig = remoteConfig,
        _snoozeStore = snoozeStore ?? FlUpdaterSnoozeStore();

  // Resolved lazily via the getter below so constructing a RemoteConfigService
  // never touches FirebaseRemoteConfig.instance until a check actually needs
  // it — that's what keeps the debug-mode-gated tests above free of any
  // Firebase test setup.
  final FirebaseRemoteConfig? _providedRemoteConfig;
  final FlUpdaterSnoozeStore _snoozeStore;
  final bool? enableLogging;

  FirebaseRemoteConfig get _remoteConfig =>
      _providedRemoteConfig ?? FirebaseRemoteConfig.instance;

  static const _knownKeys = [
    'fl_updater_latest_version',
    'fl_updater_min_version',
  ];

  static const _defaultValues = {
    'fl_updater_latest_version': '0.0.0',
    'fl_updater_min_version': '0.0.0',
  };

  Future<UpdateInfo> checkForUpdate({
    Duration snoozeDuration = const Duration(days: 3),
    Duration minimumFetchInterval = const Duration(hours: 1),
    bool enabled = !kDebugMode,
    bool clearSnoozeInDebugMode = false,
    bool? enableLogging,
    String? iosAppId,
    String? androidPackageId,
  }) async {
    // `enabled` is the master gate and takes precedence over every other
    // parameter below (enableLogging, clearSnoozeInDebugMode) — checked
    // first, before any of them are acted on.
    final logging = enableLogging ?? this.enableLogging;
    if (!enabled) {
      FlUpdaterLogger.log(
        'Update check skipped (enabled is false).',
        enableLogging: logging,
      );
      return UpdateInfo(
        currentVersion: '',
        latestVersion: '',
        status: UpdateStatus.none,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );
    }

    FlUpdaterLogger.log(
      'Checking for update with snoozeDuration=$snoozeDuration, '
      'minimumFetchInterval=$minimumFetchInterval, enabled=$enabled, '
      'clearSnoozeInDebugMode=$clearSnoozeInDebugMode, '
      'iosAppId=$iosAppId, androidPackageId=$androidPackageId',
      enableLogging: logging,
    );

    if (kDebugMode && clearSnoozeInDebugMode) {
      FlUpdaterLogger.log(
        'clearSnoozeInDebugMode is enabled: clearing snooze store in debug mode.',
        enableLogging: logging,
      );
      await _snoozeStore.clear();
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      FlUpdaterLogger.log('Current installed version: $currentVersion',
          enableLogging: logging);

      try {
        await _remoteConfig.setConfigSettings(
          RemoteConfigSettings(
            fetchTimeout: const Duration(minutes: 1),
            minimumFetchInterval: minimumFetchInterval,
          ),
        );
        await _remoteConfig.setDefaults(_defaultValues);
        await _remoteConfig.fetchAndActivate();
      } catch (fetchError, fetchStackTrace) {
        FlUpdaterLogger.log(
          'Remote config fetch threw error (evaluating active config): $fetchError',
          error: fetchError,
          stackTrace: fetchStackTrace,
          enableLogging: logging,
        );
      }

      final values = {
        for (final key in _knownKeys) key: _remoteConfig.getString(key)
      };

      var info = UpdateInfo.fromRemoteConfigValues(
        values: values,
        currentVersion: currentVersion,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );

      FlUpdaterLogger.log('Fetched remote config values: $values',
          enableLogging: logging);
      FlUpdaterLogger.log('Evaluated update status: ${info.status.name}',
          enableLogging: logging);

      if (info.status == UpdateStatus.soft &&
          await _snoozeStore.isSnoozed(info.latestVersion)) {
        FlUpdaterLogger.log(
          'Version ${info.latestVersion} is currently snoozed; setting status to none.',
          enableLogging: logging,
        );
        info = info.copyWith(status: UpdateStatus.none);
      }

      return info;
    } catch (error, stackTrace) {
      FlUpdaterLogger.log(
        'Failed to fetch remote config: $error',
        error: error,
        stackTrace: stackTrace,
        enableLogging: logging,
      );
      return UpdateInfo(
        currentVersion: '',
        latestVersion: '',
        status: UpdateStatus.none,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );
    }
  }

  /// Evaluates the already-active values in Firebase Remote Config without performing a network fetch.
  ///
  /// When [clearSnooze] is `true` (default for real-time updates), clears the snooze store
  /// so that newly published updates prompt the user immediately.
  Future<UpdateInfo> evaluateActiveConfig({
    String? iosAppId,
    String? androidPackageId,
    bool clearSnooze = true,
    bool? enableLogging,
  }) async {
    final logging = enableLogging ?? this.enableLogging;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (clearSnooze) {
        FlUpdaterLogger.log(
          'Clearing snooze store on real-time update evaluation.',
          enableLogging: logging,
        );
        await _snoozeStore.clear();
      }

      final values = {
        for (final key in _knownKeys) key: _remoteConfig.getString(key)
      };

      var info = UpdateInfo.fromRemoteConfigValues(
        values: values,
        currentVersion: currentVersion,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );

      FlUpdaterLogger.log('Active remote config values: $values',
          enableLogging: logging);
      FlUpdaterLogger.log('Evaluated update status: ${info.status.name}',
          enableLogging: logging);

      if (!clearSnooze &&
          info.status == UpdateStatus.soft &&
          await _snoozeStore.isSnoozed(info.latestVersion)) {
        FlUpdaterLogger.log(
          'Version ${info.latestVersion} is currently snoozed; setting status to none.',
          enableLogging: logging,
        );
        info = info.copyWith(status: UpdateStatus.none);
      }

      return info;
    } catch (error, stackTrace) {
      FlUpdaterLogger.log(
        'Failed to evaluate active remote config: $error',
        error: error,
        stackTrace: stackTrace,
        enableLogging: logging,
      );
      return UpdateInfo(
        currentVersion: '',
        latestVersion: '',
        status: UpdateStatus.none,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );
    }
  }

  /// Listens to real-time Remote Config updates using [FirebaseRemoteConfig.onConfigUpdated].
  ///
  /// When [fl_updater_latest_version] or [fl_updater_min_version] changes (or when a general
  /// template update is pushed), activates the updated values immediately and calls [onConfigUpdated].
  StreamSubscription<RemoteConfigUpdate>? listenForUpdates(
    Future<void> Function() onConfigUpdated, {
    bool? enableLogging,
  }) {
    try {
      final logging = enableLogging ?? this.enableLogging;
      return _remoteConfig.onConfigUpdated.listen(
        (event) async {
          FlUpdaterLogger.log(
            'Real-time Remote Config update received for keys: ${event.updatedKeys}',
            enableLogging: logging,
          );
          if (event.updatedKeys.isEmpty ||
              event.updatedKeys.contains('fl_updater_latest_version') ||
              event.updatedKeys.contains('fl_updater_min_version')) {
            try {
              final activated = await _remoteConfig.activate();
              FlUpdaterLogger.log(
                'Activated real-time Remote Config update (new values activated: $activated).',
                enableLogging: logging,
              );
            } catch (err, st) {
              FlUpdaterLogger.log(
                'Failed to activate real-time Remote Config update: $err',
                error: err,
                stackTrace: st,
                enableLogging: logging,
              );
            }
            await onConfigUpdated();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          FlUpdaterLogger.log(
            'Error in real-time Remote Config update stream: $error',
            error: error,
            stackTrace: stackTrace,
            enableLogging: logging,
          );
        },
      );
    } catch (error, stackTrace) {
      FlUpdaterLogger.log(
        'Failed to subscribe to real-time Remote Config updates: $error',
        error: error,
        stackTrace: stackTrace,
        enableLogging: enableLogging ?? this.enableLogging,
      );
      return null;
    }
  }
}
