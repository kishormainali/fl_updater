import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:fp_logger/fp_logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/update_info.model.dart';
import '../models/update_status.dart';
import '../providers/config_provider.dart';
import '../utils/logging.dart';
import 'snooze_store.dart';

class UpdateService {
  UpdateService({
    required FlUpdaterConfigProvider provider,
    FlUpdaterSnoozeStore? snoozeStore,
    this.enableLogging,
  })  : _provider = provider,
        _snoozeStore = snoozeStore ?? FlUpdaterSnoozeStore();

  final FlUpdaterConfigProvider _provider;
  final FlUpdaterSnoozeStore _snoozeStore;
  final bool? enableLogging;

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

  /// Combines [PackageInfo.version] and [PackageInfo.buildNumber] into the
  /// `x.x.x+x` form [VersionComparator] expects, so an installed build is
  /// compared correctly against a config `min_version`/`latest_version`
  /// that specifies a build number. [PackageInfo.version] alone never
  /// contains the build number — leaving it off would make every install
  /// compare as build `0`, incorrectly forcing an update whenever the config
  /// specifies a build-number requirement above zero.
  static String _currentVersion(PackageInfo packageInfo) {
    final buildNumber = packageInfo.buildNumber;
    return buildNumber.isEmpty
        ? packageInfo.version
        : '${packageInfo.version}+$buildNumber';
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
    final logging =
        (enableLogging ?? this.enableLogging) ?? flUpdaterLoggingEnabled;
    if (!enabled) {
      if (logging) {
        Logger.i('Update check skipped (enabled is false).',
            tag: flUpdaterLogTag);
      }
      return UpdateInfo(
        currentVersion: '',
        latestVersion: '',
        status: UpdateStatus.none,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );
    }

    if (kDebugMode && clearSnoozeInDebugMode) {
      if (logging) {
        Logger.i(
          'clearSnoozeInDebugMode is enabled: clearing snooze store in debug mode.',
          tag: flUpdaterLogTag,
        );
      }
      await _snoozeStore.clear();
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _currentVersion(packageInfo);

      String? rawConfig;
      try {
        rawConfig = await _provider.fetch(
          minimumFetchInterval: minimumFetchInterval,
        );
      } catch (fetchError, fetchStackTrace) {
        if (logging) {
          Logger.e(
            'Config fetch threw error (falling back to current config): $fetchError',
            error: fetchError,
            stackTrace: fetchStackTrace,
            tag: flUpdaterLogTag,
          );
        }
        rawConfig = await _provider.current();
      }

      var info = UpdateInfo.fromRemoteConfigJson(
        json: rawConfig,
        currentVersion: currentVersion,
        flavor: flavor,
        platform: resolvedPlatform,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );

      if (logging) {
        // Passed separately (rather than interpolated into the summary line
        // below) so fp_logger's auto-detection pretty-prints the JSON with
        // indentation instead of dumping it as one unreadable minified blob.
        Logger.i(rawConfig, tag: flUpdaterLogTag);
        Logger.i(
          'checkForUpdate: flavor=$flavor platform=$resolvedPlatform '
          'current=$currentVersion -> latest=${info.latestVersion} '
          'status=${info.status.name}',
          tag: flUpdaterLogTag,
        );
      }

      if (info.status == UpdateStatus.soft &&
          await _snoozeStore.isSnoozed(info.latestVersion)) {
        if (logging) {
          Logger.i(
            'Version ${info.latestVersion} is currently snoozed; setting status to none.',
            tag: flUpdaterLogTag,
          );
        }
        info = info.copyWith(status: UpdateStatus.none);
      }

      return info;
    } catch (error, stackTrace) {
      if (logging) {
        Logger.e(
          'Failed to fetch update config: $error',
          error: error,
          stackTrace: stackTrace,
          tag: flUpdaterLogTag,
        );
      }
      return UpdateInfo(
        currentVersion: '',
        latestVersion: '',
        status: UpdateStatus.none,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );
    }
  }

  /// Evaluates the provider's current (already-active) config without performing a network fetch.
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
    final logging =
        (enableLogging ?? this.enableLogging) ?? flUpdaterLoggingEnabled;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _currentVersion(packageInfo);

      if (clearSnooze) {
        if (logging) {
          Logger.i(
            'Clearing snooze store on real-time update evaluation.',
            tag: flUpdaterLogTag,
          );
        }
        await _snoozeStore.clear();
      }

      final rawConfig = await _provider.current();

      var info = UpdateInfo.fromRemoteConfigJson(
        json: rawConfig,
        currentVersion: currentVersion,
        flavor: flavor,
        platform: resolvedPlatform,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );

      if (logging) {
        // Passed separately (rather than interpolated into the summary line
        // below) so fp_logger's auto-detection pretty-prints the JSON with
        // indentation instead of dumping it as one unreadable minified blob.
        Logger.i(rawConfig, tag: flUpdaterLogTag);
        Logger.i(
          'evaluateActiveConfig: flavor=$flavor platform=$resolvedPlatform '
          'current=$currentVersion -> latest=${info.latestVersion} '
          'status=${info.status.name}',
          tag: flUpdaterLogTag,
        );
      }

      if (!clearSnooze &&
          info.status == UpdateStatus.soft &&
          await _snoozeStore.isSnoozed(info.latestVersion)) {
        if (logging) {
          Logger.i(
            'Version ${info.latestVersion} is currently snoozed; setting status to none.',
            tag: flUpdaterLogTag,
          );
        }
        info = info.copyWith(status: UpdateStatus.none);
      }

      return info;
    } catch (error, stackTrace) {
      if (logging) {
        Logger.e(
          'Failed to evaluate active update config: $error',
          error: error,
          stackTrace: stackTrace,
          tag: flUpdaterLogTag,
        );
      }
      return UpdateInfo(
        currentVersion: '',
        latestVersion: '',
        status: UpdateStatus.none,
        iosAppId: iosAppId,
        androidPackageId: androidPackageId,
      );
    }
  }

  /// Subscribes to the provider's [FlUpdaterConfigProvider.changes] stream and
  /// calls [onConfigUpdated] for each event. Returns `null` when the provider
  /// has no push support.
  StreamSubscription<void>? listenForUpdates(
    Future<void> Function() onConfigUpdated, {
    bool? enableLogging,
  }) {
    final logging =
        (enableLogging ?? this.enableLogging) ?? flUpdaterLoggingEnabled;
    try {
      final stream = _provider.changes;
      if (stream == null) return null;
      return stream.listen(
        (_) async {
          if (logging) {
            Logger.i('Config change received.', tag: flUpdaterLogTag);
          }
          await onConfigUpdated();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (logging) {
            Logger.e(
              'Error in config change stream: $error',
              error: error,
              stackTrace: stackTrace,
              tag: flUpdaterLogTag,
            );
          }
        },
      );
    } catch (error, stackTrace) {
      if (logging) {
        Logger.e(
          'Failed to subscribe to config changes: $error',
          error: error,
          stackTrace: stackTrace,
          tag: flUpdaterLogTag,
        );
      }
      return null;
    }
  }
}
