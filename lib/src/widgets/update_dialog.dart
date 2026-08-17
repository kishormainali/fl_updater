import 'package:flutter/material.dart';

import '../models/update_info.model.dart';
import '../models/update_status.dart';

typedef FlUpdaterDialogBuilder = Widget Function(
  BuildContext context,
  UpdateInfo info,
  VoidCallback onUpdate,
  VoidCallback onLater,
);

class FlUpdaterDialogStyle {
  const FlUpdaterDialogStyle({
    this.backgroundColor,
    this.titleStyle,
    this.messageStyle,
    this.shape,
    this.icon,
    this.updateButtonStyle,
    this.laterButtonStyle,
    this.barrierColor,
  });

  final Color? backgroundColor;
  final TextStyle? titleStyle;
  final TextStyle? messageStyle;
  final ShapeBorder? shape;
  final Widget? icon;
  final ButtonStyle? updateButtonStyle;
  final ButtonStyle? laterButtonStyle;
  final Color? barrierColor;
}

class FlUpdaterDialog extends StatelessWidget {
  const FlUpdaterDialog({
    super.key,
    required this.info,
    required this.onUpdate,
    required this.onLater,
    this.title,
    this.message,
    this.updateButtonText,
    this.laterButtonText,
    this.style,
  });

  final UpdateInfo info;
  final VoidCallback onUpdate;
  final VoidCallback onLater;
  final String? title;
  final String? message;
  final String? updateButtonText;
  final String? laterButtonText;
  final FlUpdaterDialogStyle? style;

  bool get _isForce => info.status == UpdateStatus.force;

  @override
  Widget build(BuildContext context) {
    final dialog = AlertDialog(
      backgroundColor: style?.backgroundColor,
      shape: style?.shape,
      icon: style?.icon,
      title: Text(title ?? 'Update available', style: style?.titleStyle),
      content: Text(
        message ??
            (_isForce
                ? 'A required update is available. Please update to continue using the app.'
                : 'A new version (${info.latestVersion}) is available.'),
        style: style?.messageStyle,
      ),
      actions: [
        if (!_isForce)
          TextButton(
            key: const Key('fl_updater_later_button'),
            style: style?.laterButtonStyle,
            onPressed: onLater,
            child: Text(laterButtonText ?? 'Later'),
          ),
        FilledButton(
          key: const Key('fl_updater_update_button'),
          style: style?.updateButtonStyle,
          onPressed: onUpdate,
          child: Text(updateButtonText ?? 'Update'),
        ),
      ],
    );

    if (_isForce) {
      return PopScope(canPop: false, child: dialog);
    }
    return dialog;
  }
}
