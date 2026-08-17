/// A Flutter plugin that provides Firebase Remote Config-driven app update
/// checking, snoozable soft updates, blocking force updates, and native
/// App Store / Google Play Store redirection.
library;

import 'package:flutter/material.dart';

import 'src/models/update_info.model.dart';
import 'src/services/remote_config_service.dart';
import 'src/services/snooze_store.dart';
import 'src/widgets/dialog_presenter.dart';
import 'src/widgets/update_dialog.dart';

export 'src/models/update_info.model.dart';
export 'src/models/update_status.dart';
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
  })  : _remoteConfigService = remoteConfigService ?? RemoteConfigService(),
        _snoozeStore = snoozeStore ?? FlUpdaterSnoozeStore();

  final RemoteConfigService _remoteConfigService;
  final FlUpdaterSnoozeStore _snoozeStore;

  /// Fetches Firebase Remote Config and computes the current [UpdateInfo].
  ///
  /// - [snoozeDuration]: How long a soft update remains snoozed when dismissed.
  /// - [minimumFetchInterval]: Throttling duration for Remote Config fetches.
  /// - [enableInDebugMode]: Whether to execute Remote Config checks in debug mode
  ///   (defaults to `false` to avoid unintended fetches during local development).
  /// - [iosAppId]: The Apple App Store numeric ID (e.g. `'123456789'`).
  /// - [androidPackageId]: The Google Play Store package name (defaults to host app's package name if omitted).
  Future<UpdateInfo> checkForUpdate({
    Duration snoozeDuration = const Duration(days: 3),
    Duration minimumFetchInterval = const Duration(hours: 12),
    bool enableInDebugMode = false,
    String? iosAppId,
    String? androidPackageId,
  }) {
    return _remoteConfigService.checkForUpdate(
      snoozeDuration: snoozeDuration,
      minimumFetchInterval: minimumFetchInterval,
      enableInDebugMode: enableInDebugMode,
      iosAppId: iosAppId,
      androidPackageId: androidPackageId,
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
    FlUpdaterDialogBuilder? dialogBuilder,
    String? title,
    String? message,
    String? updateButtonText,
    String? laterButtonText,
    FlUpdaterDialogStyle? style,
    Duration snoozeDuration = const Duration(days: 3),
    Duration minimumFetchInterval = const Duration(hours: 12),
    bool enableInDebugMode = false,
  }) async {
    final resolvedInfo = info ??
        await checkForUpdate(
          snoozeDuration: snoozeDuration,
          minimumFetchInterval: minimumFetchInterval,
          enableInDebugMode: enableInDebugMode,
          iosAppId: iosAppId,
          androidPackageId: androidPackageId,
        );
    if (!context.mounted) return;
    await presentUpdateDialog(
      context,
      info: resolvedInfo,
      snoozeStore: _snoozeStore,
      snoozeDuration: snoozeDuration,
      dialogBuilder: dialogBuilder,
      title: title,
      message: message,
      updateButtonText: updateButtonText,
      laterButtonText: laterButtonText,
      style: style,
    );
  }
}
