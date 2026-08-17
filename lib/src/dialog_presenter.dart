import 'package:flutter/material.dart';

import 'fl_updater_platform_interface.dart';
import 'models/update_info.model.dart';
import 'models/update_status.dart';
import 'snooze_store.dart';
import 'update_dialog.dart';

Future<void> presentUpdateDialog(
  BuildContext context, {
  required UpdateInfo info,
  required FlUpdaterSnoozeStore snoozeStore,
  required Duration snoozeDuration,
  FlUpdaterDialogBuilder? dialogBuilder,
  String? title,
  String? message,
  String? updateButtonText,
  String? laterButtonText,
  FlUpdaterDialogStyle? style,
}) async {
  if (info.status == UpdateStatus.none) return;
  if (!context.mounted) return;

  Future<void> onUpdate() async {
    try {
      await FlUpdaterPlatform.instance.openStore(
        iosAppId: info.iosAppId,
        androidPackageId: info.androidPackageId,
      );
    } catch (error) {
      debugPrint('fl_updater: failed to open store: $error');
    }
  }

  Future<void> onLater() async {
    await snoozeStore.snooze(info.latestVersion, snoozeDuration);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: info.status != UpdateStatus.force,
    barrierColor: style?.barrierColor,
    builder: (dialogContext) {
      if (dialogBuilder != null) {
        return dialogBuilder(dialogContext, info, onUpdate, onLater);
      }
      return FlUpdaterDialog(
        info: info,
        onUpdate: onUpdate,
        onLater: onLater,
        title: title,
        message: message,
        updateButtonText: updateButtonText,
        laterButtonText: laterButtonText,
        style: style,
      );
    },
  );
}
