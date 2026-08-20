import 'package:flutter/material.dart';
import 'package:fp_logger/fp_logger.dart';

import '../models/update_info.model.dart';
import '../models/update_status.dart';
import '../services/fl_updater_platform_interface.dart';
import '../services/snooze_store.dart';
import '../utils/logging.dart';
import 'update_dialog.dart';

/// Finds a [BuildContext] that is or has an ancestor [NavigatorState].
///
/// When [FlUpdaterWrapper] is used inside `MaterialApp.builder`, the wrapper's
/// context is an ancestor of the [Navigator] (inside `child`). This function
/// finds the root [NavigatorState] in the widget tree so that [showDialog]
/// can be presented properly without throwing a missing Navigator error.
///
/// The search first looks at [context] itself (as an ancestor or as a
/// descendant of it), and if that fails, falls back to searching the whole
/// app from [WidgetsBinding.rootElement] downward. The fallback covers apps
/// where [FlUpdaterWrapper] isn't a strict ancestor of the actual Navigator
/// (e.g. it sits alongside rather than above it), which is what causes the
/// "context ... must be that of a widget that is a descendant of a Navigator
/// widget" crash when the local search comes up empty.
BuildContext findNavigatorContext(
  BuildContext context, {
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  if (navigatorKey?.currentState != null) {
    return _navigatorUsableContext(navigatorKey!.currentState!);
  }
  if (navigatorKey?.currentContext != null) {
    return navigatorKey!.currentContext!;
  }

  final nav = _findNavigatorState(context) ??
      _findNavigatorState(WidgetsBinding.instance.rootElement);
  if (nav != null) {
    return _navigatorUsableContext(nav);
  }

  return context;
}

/// Looks for a [NavigatorState] that is [context] itself, an ancestor of it,
/// or a descendant of it (in that order).
NavigatorState? _findNavigatorState(BuildContext? context) {
  if (context == null) return null;

  final ancestorOrSelf = Navigator.maybeOf(context, rootNavigator: true) ??
      Navigator.maybeOf(context);
  if (ancestorOrSelf != null) return ancestorOrSelf;

  NavigatorState? descendantNav;
  void visitor(Element element) {
    if (descendantNav != null) return;
    if (element is StatefulElement && element.state is NavigatorState) {
      descendantNav = element.state as NavigatorState;
      return;
    }
    element.visitChildren(visitor);
  }

  if (context is Element) {
    context.visitChildren(visitor);
  }

  return descendantNav;
}

/// Returns a [BuildContext] that is a genuine descendant of [nav], suitable
/// for passing to [Navigator.of]/[showDialog].
///
/// [NavigatorState.overlay] is built inside the Navigator, so its context
/// reliably resolves back to [nav] via an ancestor search, unlike relying on
/// [NavigatorState.context] (the Navigator's own element) directly.
BuildContext _navigatorUsableContext(NavigatorState nav) {
  return nav.overlay?.context ?? nav.context;
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
  if (info.status == UpdateStatus.none) return;
  if (!context.mounted) return;

  final navContext = findNavigatorContext(context, navigatorKey: navigatorKey);
  if (!navContext.mounted) return;

  final logging = enableLogging ?? flUpdaterLoggingEnabled;
  if (logging) {
    Logger.i(
      'Presenting update dialog for status: ${info.status.name}',
      tag: flUpdaterLogTag,
    );
  }

  Future<void> onUpdate() async {
    try {
      if (logging) {
        Logger.i(
          'Opening store (iosAppId: ${info.iosAppId}, androidPackageId: ${info.androidPackageId})',
          tag: flUpdaterLogTag,
        );
      }
      await FlUpdaterPlatform.instance.openStore(
        iosAppId: info.iosAppId,
        androidPackageId: info.androidPackageId,
      );
    } catch (error, stackTrace) {
      if (logging) {
        Logger.e(
          'Failed to open store: $error',
          error: error,
          stackTrace: stackTrace,
          tag: flUpdaterLogTag,
        );
      }
    }
  }

  Future<void> onLater() async {
    try {
      if (logging) {
        Logger.i(
          'Snoozing version ${info.latestVersion} for $snoozeDuration',
          tag: flUpdaterLogTag,
        );
      }
      await snoozeStore.snooze(info.latestVersion, snoozeDuration);
    } catch (error, stackTrace) {
      if (logging) {
        Logger.e(
          'Failed to record snooze: $error',
          error: error,
          stackTrace: stackTrace,
          tag: flUpdaterLogTag,
        );
      }
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
