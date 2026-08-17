import 'package:flutter/material.dart';

import '../services/remote_config_service.dart';
import '../services/snooze_store.dart';
import 'dialog_presenter.dart';
import 'update_dialog.dart';

/// A declarative wrapper widget that automatically checks Firebase Remote Config
/// on launch and presents an update dialog if an update is available.
///
/// Typically used in the `builder` callback of [MaterialApp]:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => FlUpdaterWrapper(
///     iosAppId: '123456789',
///     androidPackageId: 'com.example.app',
///     child: child!,
///   ),
///   home: const HomeScreen(),
/// )
/// ```
class FlUpdaterWrapper extends StatefulWidget {
  /// Creates an [FlUpdaterWrapper] that guards [child] with automatic update checks.
  const FlUpdaterWrapper({
    super.key,
    required this.child,
    this.iosAppId,
    this.androidPackageId,
    this.dialogBuilder,
    this.title,
    this.message,
    this.updateButtonText,
    this.laterButtonText,
    this.style,
    this.snoozeDuration = const Duration(days: 3),
    this.minimumFetchInterval = const Duration(hours: 12),
    this.enableInDebugMode = false,
  });

  /// The child widget to display (typically the app navigator or screen).
  final Widget child;

  /// The numeric App Store identifier for iOS (e.g. `'123456789'`).
  ///
  /// Required on iOS for redirecting users to the Apple App Store.
  final String? iosAppId;

  /// The Android package name for the Google Play Store (e.g. `'com.example.app'`).
  ///
  /// Defaults to the host application's package name if omitted.
  final String? androidPackageId;

  /// An optional custom builder to render a bespoke update UI instead of the
  /// built-in dialog.
  final FlUpdaterDialogBuilder? dialogBuilder;

  /// Custom dialog title text. Defaults to `'Update available'`.
  final String? title;

  /// Custom dialog message body text.
  final String? message;

  /// Custom text for the update action button. Defaults to `'Update'`.
  final String? updateButtonText;

  /// Custom text for the snooze/dismiss button on soft updates. Defaults to `'Later'`.
  final String? laterButtonText;

  /// Visual styling configuration for the built-in dialog.
  final FlUpdaterDialogStyle? style;

  /// Duration to snooze soft updates when dismissed via the later button.
  /// Defaults to 3 days.
  final Duration snoozeDuration;

  /// Minimum interval between real Firebase Remote Config network fetches.
  /// Defaults to 12 hours.
  final Duration minimumFetchInterval;

  /// Whether to enable update checking in debug mode.
  ///
  /// Defaults to `false` so development hot restarts do not consume Remote Config
  /// quota or interrupt development flow.
  final bool enableInDebugMode;

  @override
  State<FlUpdaterWrapper> createState() => _FlUpdaterWrapperState();
}

class _FlUpdaterWrapperState extends State<FlUpdaterWrapper> {
  final _remoteConfigService = RemoteConfigService();
  final _snoozeStore = FlUpdaterSnoozeStore();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    final info = await _remoteConfigService.checkForUpdate(
      snoozeDuration: widget.snoozeDuration,
      minimumFetchInterval: widget.minimumFetchInterval,
      enableInDebugMode: widget.enableInDebugMode,
      iosAppId: widget.iosAppId,
      androidPackageId: widget.androidPackageId,
    );
    if (!mounted) return;
    await presentUpdateDialog(
      context,
      info: info,
      snoozeStore: _snoozeStore,
      snoozeDuration: widget.snoozeDuration,
      dialogBuilder: widget.dialogBuilder,
      title: widget.title,
      message: widget.message,
      updateButtonText: widget.updateButtonText,
      laterButtonText: widget.laterButtonText,
      style: widget.style,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
