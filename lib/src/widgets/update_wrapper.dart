import 'package:flutter/material.dart';

import '../services/remote_config_service.dart';
import '../services/snooze_store.dart';
import 'dialog_presenter.dart';
import 'update_dialog.dart';

class FlUpdaterWrapper extends StatefulWidget {
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

  final Widget child;
  final String? iosAppId;
  final String? androidPackageId;
  final FlUpdaterDialogBuilder? dialogBuilder;
  final String? title;
  final String? message;
  final String? updateButtonText;
  final String? laterButtonText;
  final FlUpdaterDialogStyle? style;
  final Duration snoozeDuration;
  final Duration minimumFetchInterval;
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
