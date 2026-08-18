import 'package:flutter/material.dart';

import '../models/update_info.model.dart';
import '../models/update_status.dart';
import '../services/fl_updater_platform_interface.dart';
import '../services/snooze_store.dart';
import '../utils/logger.dart';
import 'update_dialog.dart';

/// Finds a [BuildContext] that is or has an ancestor [NavigatorState].
///
/// When [FlUpdaterWrapper] is used inside `MaterialApp.builder`, the wrapper's
/// context is an ancestor of the [Navigator] (inside `child`). This function
/// finds the root [NavigatorState] in the widget tree so that [showDialog]
/// can be presented properly without throwing a missing Navigator error.
BuildContext findNavigatorContext(
  BuildContext context, {
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  if (navigatorKey?.currentContext != null) {
    return navigatorKey!.currentContext!;
  }

  // Check if context has an ancestor Navigator or is itself a Navigator.
  final nav = Navigator.maybeOf(context, rootNavigator: true) ??
      Navigator.maybeOf(context);
  if (nav != null) {
    return nav.context;
  }

  // If not found in ancestors, search down the element tree (descendants).
  NavigatorState? descendantNav;
  void visitor(Element element) {
    if (element is StatefulElement && element.state is NavigatorState) {
      descendantNav = element.state as NavigatorState;
      return;
    }
    element.visitChildren(visitor);
  }

  if (context is Element) {
    context.visitChildren(visitor);
  }

  if (descendantNav != null) {
    return descendantNav!.context;
  }

  return context;
}

Future<void> presentUpdateDialog(
  BuildContext context, {
  required UpdateInfo info,
  required FlUpdaterSnoozeStore snoozeStore,
  required Duration snoozeDuration,
  GlobalKey<NavigatorState>? navigatorKey,
  FlUpdaterDialogBuilder? dialogBuilder,
  String? title,
  String? message,
  String? updateButtonText,
  String? laterButtonText,
  FlUpdaterDialogStyle? style,
  bool? enableLogging,
}) async {
  if (info.status == UpdateStatus.none) {
    FlUpdaterLogger.log(
      'No update dialog to present (status: none).',
      enableLogging: enableLogging,
    );
    return;
  }
  if (!context.mounted) return;

  final navContext = findNavigatorContext(context, navigatorKey: navigatorKey);
  if (!navContext.mounted) return;

  FlUpdaterLogger.log(
    'Presenting update dialog for status: ${info.status.name}',
    enableLogging: enableLogging,
  );

  Future<void> onUpdate() async {
    try {
      FlUpdaterLogger.log(
        'Opening store (iosAppId: ${info.iosAppId}, androidPackageId: ${info.androidPackageId})',
        enableLogging: enableLogging,
      );
      await FlUpdaterPlatform.instance.openStore(
        iosAppId: info.iosAppId,
        androidPackageId: info.androidPackageId,
      );
    } catch (error, stackTrace) {
      FlUpdaterLogger.log(
        'Failed to open store: $error',
        error: error,
        stackTrace: stackTrace,
        enableLogging: enableLogging,
      );
    }
  }

  Future<void> onLater() async {
    try {
      FlUpdaterLogger.log(
        'Snoozing version ${info.latestVersion} for $snoozeDuration',
        enableLogging: enableLogging,
      );
      await snoozeStore.snooze(info.latestVersion, snoozeDuration);
    } catch (error, stackTrace) {
      FlUpdaterLogger.log(
        'Failed to record snooze: $error',
        error: error,
        stackTrace: stackTrace,
        enableLogging: enableLogging,
      );
    }
    if (navContext.mounted) {
      Navigator.of(navContext, rootNavigator: true).pop();
    }
  }

  await showDialog<void>(
    context: navContext,
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
