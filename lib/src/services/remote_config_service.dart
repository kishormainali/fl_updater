import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
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

  static const _configKey = 'fl_updater_config';

  static const _defaultValues = {_configKey: '{}'};

  /// Maps [defaultTargetPlatform] to the `platforms` key used in the
  /// `fl_updater_config` JSON schema (`'android'` / `'ios'`), or `null` on
  /// platforms with no dedicated key (web, desktop) so platform-scoped
  /// lookups simply fall through to flavor/top-level values.
  ///
  /// Not usable as a parameter default (unlike [appFlavor]) since
  /// [defaultTargetPlatform] isn't a compile-time constant — resolved at
  /// call time instead whenever [platform] isn't passed explicitly.
  static String? _currentPlatformName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return null;
    }
  }

  Future<UpdateInfo> checkForUpdate({
    Duration snoozeDuration = const Duration(days: 3),
    Duration minimumFetchInterval = const Duration(hours: 1),
    bool enabled = !kDebugMode,
    bool clearSnoozeInDebugMode = false,
    bool? enableLogging,
    String? iosAppId,
    String? androidPackageId,
    String? flavor = appFlavor,
    String? platform,
  }) async {
    final resolvedPlatform = platform ?? _currentPlatformName();
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

      final rawConfig = _remoteConfig.getString(_configKey);

      var info = UpdateInfo.fromRemoteConfigJson(
        json: rawConfig,
        currentVersion: currentVersion,
        flavor: flavor,
        platform: resolvedPlatform,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );

      FlUpdaterLogger.log(
        'checkForUpdate: flavor=$flavor platform=$resolvedPlatform current=$currentVersion '
        'config=$rawConfig -> latest=${info.latestVersion} status=${info.status.name}',
        enableLogging: logging,
      );

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
    String? flavor = appFlavor,
    String? platform,
  }) async {
    final resolvedPlatform = platform ?? _currentPlatformName();
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

      final rawConfig = _remoteConfig.getString(_configKey);

      var info = UpdateInfo.fromRemoteConfigJson(
        json: rawConfig,
        currentVersion: currentVersion,
        flavor: flavor,
        platform: resolvedPlatform,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );

      FlUpdaterLogger.log(
        'evaluateActiveConfig: flavor=$flavor platform=$resolvedPlatform current=$currentVersion '
        'config=$rawConfig -> latest=${info.latestVersion} status=${info.status.name}',
        enableLogging: logging,
      );

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
  /// When the `fl_updater_config` parameter changes (or when a general template
  /// update is pushed), activates the updated value immediately and calls
  /// [onConfigUpdated].
  StreamSubscription<RemoteConfigUpdate>? listenForUpdates(
    Future<void> Function() onConfigUpdated, {
    bool? enableLogging,
  }) {
    try {
      final logging = enableLogging ?? this.enableLogging;
      return _remoteConfig.onConfigUpdated.listen(
        (event) async {
          if (event.updatedKeys.isEmpty ||
              event.updatedKeys.contains(_configKey)) {
            FlUpdaterLogger.log(
              'Real-time update received for $_configKey (keys: ${event.updatedKeys}).',
              enableLogging: logging,
            );
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
