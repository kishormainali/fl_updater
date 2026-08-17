import 'package:flutter/material.dart';

import '../models/update_info.model.dart';
import '../models/update_status.dart';

/// Signature for a builder function that constructs a custom update dialog or UI.
///
/// - [context]: The current build context.
/// - [info]: The resolved [UpdateInfo] with current version, latest version, and status.
/// - [onUpdate]: Callback to invoke to redirect the user to the platform's app store.
/// - [onLater]: Callback to invoke to snooze the update and dismiss the dialog.
typedef FlUpdaterDialogBuilder = Widget Function(
  BuildContext context,
  UpdateInfo info,
  VoidCallback onUpdate,
  VoidCallback onLater,
);

/// Style configuration options for the default [FlUpdaterDialog].
class FlUpdaterDialogStyle {
  /// Creates an [FlUpdaterDialogStyle].
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

  /// Background color of the dialog surface.
  final Color? backgroundColor;

  /// Text style for the dialog title.
  final TextStyle? titleStyle;

  /// Text style for the dialog message content.
  final TextStyle? messageStyle;

  /// Shape of the dialog frame (e.g. [RoundedRectangleBorder]).
  final ShapeBorder? shape;

  /// Optional icon widget displayed at the top of the dialog.
  final Widget? icon;

  /// Button style for the primary "Update" button.
  final ButtonStyle? updateButtonStyle;

  /// Button style for the secondary "Later" button.
  final ButtonStyle? laterButtonStyle;

  /// Barrier color surrounding the dialog overlay.
  final Color? barrierColor;
}

/// The built-in Material update dialog used by `fl_updater`.
class FlUpdaterDialog extends StatelessWidget {
  /// Creates a built-in update dialog.
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

  /// Information about the update, such as version numbers and [UpdateStatus].
  final UpdateInfo info;

  /// Callback to execute when the user taps the update button.
  final VoidCallback onUpdate;

  /// Callback to execute when the user taps the later/snooze button.
  final VoidCallback onLater;

  /// Custom title text. Defaults to `'Update available'`.
  final String? title;

  /// Custom message text. If null, standard default copy is used.
  final String? message;

  /// Label for the update button. Defaults to `'Update'`.
  final String? updateButtonText;

  /// Label for the later button. Defaults to `'Later'`.
  final String? laterButtonText;

  /// Visual styling configuration for the dialog.
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
