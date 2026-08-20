/// A Flutter plugin that provides Firebase Remote Config-driven app update
/// checking, snoozable soft updates, blocking force updates, and native
/// App Store / Google Play Store redirection.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;

import 'src/models/update_info.model.dart';
import 'src/services/remote_config_service.dart';
import 'src/services/snooze_store.dart';
import 'src/utils/logger.dart';
import 'src/widgets/dialog_presenter.dart';
import 'src/widgets/update_dialog.dart';

export 'src/models/update_info.model.dart';
export 'src/models/update_status.dart';
export 'src/services/snooze_store.dart' show FlUpdaterSnoozeStore;
export 'src/utils/logger.dart' show FlUpdaterLogger;
export 'src/widgets/update_dialog.dart'
    show FlUpdaterDialog, FlUpdaterDialogBuilder, FlUpdaterDialogStyle;
export 'src/widgets/update_wrapper.dart';

/// Provides programmatic methods to check for updates and present the update dialog.
///
/// For declarative automatic checking on app launch, see [FlUpdaterWrapper].
class FlUpdater {
  /// Creates a new [FlUpdater] instance.
  ///
  /// Optionally accepts a custom [remoteConfigService] or [snoozeStore]
  /// for dependency injection and testing.
  FlUpdater({
    RemoteConfigService? remoteConfigService,
    FlUpdaterSnoozeStore? snoozeStore,
    bool? enableLogging,
  })  : _remoteConfigService = remoteConfigService ?? RemoteConfigService(),
        _snoozeStore = snoozeStore ?? FlUpdaterSnoozeStore(),
        _enableLogging = enableLogging;

  /// Global flag to enable or disable diagnostic logging across fl_updater.
  ///
  /// Defaults to `false`.
  static bool get enableLogging => FlUpdaterLogger.enabled;
  static set enableLogging(bool value) => FlUpdaterLogger.enabled = value;

  /// Clears any active snooze state from local storage globally.
  ///
  /// Useful for debugging and testing update prompts without waiting for snooze expiry.
  static Future<void> clearSnoozeStore() async {
    FlUpdaterLogger.log('Clearing snooze store globally.');
    await FlUpdaterSnoozeStore().clear();
  }

  /// Optional per-instance override for diagnostic logging.
  final bool? _enableLogging;

  final RemoteConfigService _remoteConfigService;
  final FlUpdaterSnoozeStore _snoozeStore;

  /// Clears any active snooze state from local storage.
  ///
  /// Useful for debugging and testing update prompts without waiting for snooze expiry.
  Future<void> clearSnooze() async {
    FlUpdaterLogger.log('Clearing snooze store.',
        enableLogging: _enableLogging);
    await _snoozeStore.clear();
  }

  /// Fetches Firebase Remote Config and computes the current [UpdateInfo].
  ///
  /// - [snoozeDuration]: How long a soft update remains snoozed when dismissed.
  /// - [minimumFetchInterval]: Throttling duration for Remote Config fetches.
  /// - [enabled]: Global gate for the check. Defaults to `!kDebugMode` to avoid
  ///   unintended fetches during local development; pass `true` explicitly to
  ///   test in debug mode, or `false` to disable checking entirely.
  /// - [clearSnoozeInDebugMode]: Whether to clear any stored snooze state when running in debug mode.
  ///   Only takes effect when [enabled] is also `true`.
  /// - [enableLogging]: Whether to emit diagnostic logs for this check.
  /// - [iosAppId]: The Apple App Store numeric ID (e.g. `'123456789'`).
  /// - [androidPackageId]: The Google Play Store package name (defaults to host app's package name if omitted).
  /// - [flavor]: The build flavor to scope the `fl_updater_config` parameter to.
  ///   Defaults to Flutter's built-in [appFlavor]. See [FlUpdaterWrapper.platform]
  ///   for the JSON schema this looks up and how [flavor] and [platform] combine.
  /// - [platform]: The platform to scope the `fl_updater_config` parameter to.
  ///   Defaults to the current platform (`'android'` / `'ios'`).
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
  }) {
    return _remoteConfigService.checkForUpdate(
      snoozeDuration: snoozeDuration,
      minimumFetchInterval: minimumFetchInterval,
      enabled: enabled,
      clearSnoozeInDebugMode: clearSnoozeInDebugMode,
      enableLogging: enableLogging ?? _enableLogging,
      iosAppId: iosAppId,
      androidPackageId: androidPackageId,
      flavor: flavor,
      platform: platform,
    );
  }

  /// Checks for an update (or uses [info] if provided) and displays the update dialog
  /// if an update is available.
  ///
  /// If the update is [UpdateStatus.none], no dialog is shown.
  /// If the update is [UpdateStatus.force], the dialog cannot be dismissed.
  /// If the update is [UpdateStatus.soft], tapping the later button will snooze
  /// future soft update prompts for [snoozeDuration].
  Future<void> showUpdateDialog(
    BuildContext context, {
    UpdateInfo? info,
    String? iosAppId,
    String? androidPackageId,
    String? flavor = appFlavor,
    String? platform,
    GlobalKey<NavigatorState>? navigatorKey,
    FlUpdaterDialogBuilder? dialogBuilder,
    String? title,
    String? message,
    String? updateButtonText,
    String? laterButtonText,
    FlUpdaterDialogStyle? style,
    Duration snoozeDuration = const Duration(days: 3),
    Duration minimumFetchInterval = const Duration(hours: 1),
    bool enabled = !kDebugMode,
    bool clearSnoozeInDebugMode = false,
    bool? enableLogging,
  }) async {
    final resolvedLogging = enableLogging ?? _enableLogging;
    final resolvedInfo = info ??
        await checkForUpdate(
          snoozeDuration: snoozeDuration,
          minimumFetchInterval: minimumFetchInterval,
          enabled: enabled,
          clearSnoozeInDebugMode: clearSnoozeInDebugMode,
          enableLogging: resolvedLogging,
          iosAppId: iosAppId,
          androidPackageId: androidPackageId,
          flavor: flavor,
          platform: platform,
        );
    if (!context.mounted) return;
    await presentUpdateDialog(
      context,
      info: resolvedInfo,
      snoozeStore: _snoozeStore,
      snoozeDuration: snoozeDuration,
      navigatorKey: navigatorKey,
      dialogBuilder: dialogBuilder,
      title: title,
      message: message,
      updateButtonText: updateButtonText,
      laterButtonText: laterButtonText,
      style: style,
      enableLogging: resolvedLogging,
    );
  }

  /// Listens to real-time Firebase Remote Config changes.
  ///
  /// When the `fl_updater_config` parameter is published in the Firebase
  /// Console, activates the updated config and invokes [onConfigUpdated].
  StreamSubscription<dynamic>? listenForUpdates(
    Future<void> Function() onConfigUpdated, {
    bool? enableLogging,
  }) {
    return _remoteConfigService.listenForUpdates(
      onConfigUpdated,
      enableLogging: enableLogging ?? _enableLogging,
    );
  }
}
