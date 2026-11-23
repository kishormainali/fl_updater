/// A Flutter plugin that provides remote-config-driven app update
/// checking, snoozable soft updates, blocking force updates, and native
/// App Store / Google Play Store redirection.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:fp_logger/fp_logger.dart';

import 'src/models/update_info.model.dart';
import 'src/providers/config_provider.dart';
import 'src/services/update_service.dart';
import 'src/services/snooze_store.dart';
import 'src/utils/logging.dart';
import 'src/widgets/dialog_presenter.dart';
import 'src/widgets/update_dialog.dart';

export 'src/models/update_info.model.dart';
export 'src/models/update_status.dart';
export 'src/providers/api_config_provider.dart';
export 'src/providers/config_provider.dart';
export 'src/services/snooze_store.dart' show FlUpdaterSnoozeStore;
export 'src/widgets/update_dialog.dart'
    show FlUpdaterDialog, FlUpdaterDialogBuilder, FlUpdaterDialogStyle;
export 'src/widgets/update_wrapper.dart';

/// Provides programmatic methods to check for updates and present the update dialog.
///
/// For declarative automatic checking on app launch, see [FlUpdaterWrapper].
class FlUpdater {
  /// Creates a new [FlUpdater] instance.
  ///
  /// [provider] supplies the update config (e.g. `FirebaseConfigProvider` from
  /// `fl_updater_firebase`, or [ApiConfigProvider]). [updateService] and
  /// [snoozeStore] can be injected for testing.
  FlUpdater({
    required FlUpdaterConfigProvider provider,
    @visibleForTesting UpdateService? updateService,
    FlUpdaterSnoozeStore? snoozeStore,
    bool? enableLogging,
  })  : _updateService = updateService ??
            UpdateService(
              provider: provider,
              snoozeStore: snoozeStore,
              enableLogging: enableLogging,
            ),
        _snoozeStore = snoozeStore ?? FlUpdaterSnoozeStore(),
        _enableLogging = enableLogging;

  /// Global flag to enable or disable diagnostic logging across fl_updater.
  ///
  /// Defaults to `false`.
  static bool get enableLogging => flUpdaterLoggingEnabled;
  static set enableLogging(bool value) => flUpdaterLoggingEnabled = value;

  /// Clears any active snooze state from local storage globally.
  ///
  /// Useful for debugging and testing update prompts without waiting for snooze expiry.
  static Future<void> clearSnoozeStore() async {
    if (flUpdaterLoggingEnabled) {
      Logger.i('Clearing snooze store globally.', tag: flUpdaterLogTag);
    }
    await FlUpdaterSnoozeStore().clear();
  }

  /// Optional per-instance override for diagnostic logging.
  final bool? _enableLogging;

  final UpdateService _updateService;
  final FlUpdaterSnoozeStore _snoozeStore;

  /// Clears any active snooze state from local storage.
  ///
  /// Useful for debugging and testing update prompts without waiting for snooze expiry.
  Future<void> clearSnooze() async {
    if (_enableLogging ?? flUpdaterLoggingEnabled) {
      Logger.i('Clearing snooze store.', tag: flUpdaterLogTag);
    }
    await _snoozeStore.clear();
  }

  /// Fetches the update config from the provider and computes the current [UpdateInfo].
  ///
  /// - [snoozeDuration]: How long a soft update remains snoozed when dismissed.
  /// - [minimumFetchInterval]: Throttling duration for config fetches (honoured by providers that support it).
  /// - [enabled]: Global gate for the check. Defaults to `!kDebugMode` to avoid
  ///   unintended fetches during local development; pass `true` explicitly to
  ///   test in debug mode, or `false` to disable checking entirely.
  /// - [clearSnoozeInDebugMode]: Whether to clear any stored snooze state when running in debug mode.
  ///   Only takes effect when [enabled] is also `true`.
  /// - [enableLogging]: Whether to emit diagnostic logs for this check.
  /// - [iosAppId]: The Apple App Store numeric ID (e.g. `'123456789'`).
  /// - [androidPackageId]: The Google Play Store package name (defaults to host app's package name if omitted).
  /// - [flavor]: The build flavor to scope the `fl_updater_config` JSON to.
  ///   Defaults to Flutter's built-in [appFlavor]. See [FlUpdaterWrapper.platform]
  ///   for the JSON schema this looks up and how [flavor] and [platform] combine.
  /// - [platform]: The platform to scope the `fl_updater_config` JSON to.
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
    return _updateService.checkForUpdate(
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

  /// Listens to provider push updates, invoking [onConfigUpdated] on each.
  /// Returns `null` when the provider does not support push.
  StreamSubscription<dynamic>? listenForUpdates(
    Future<void> Function() onConfigUpdated, {
    bool? enableLogging,
  }) {
    return _updateService.listenForUpdates(
      onConfigUpdated,
      enableLogging: enableLogging ?? _enableLogging,
    );
  }
}
