import 'package:flutter/material.dart';

import 'src/dialog_presenter.dart';
import 'src/models/update_info.model.dart';
import 'src/remote_config_service.dart';
import 'src/snooze_store.dart';
import 'src/update_dialog.dart';

export 'src/models/update_info.model.dart';
export 'src/models/update_status.dart';
export 'src/update_dialog.dart' show FlUpdaterDialog, FlUpdaterDialogBuilder, FlUpdaterDialogStyle;
export 'src/update_wrapper.dart';

class FlUpdater {
  FlUpdater({RemoteConfigService? remoteConfigService, FlUpdaterSnoozeStore? snoozeStore})
      : _remoteConfigService = remoteConfigService ?? RemoteConfigService(),
        _snoozeStore = snoozeStore ?? FlUpdaterSnoozeStore();

  final RemoteConfigService _remoteConfigService;
  final FlUpdaterSnoozeStore _snoozeStore;

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
