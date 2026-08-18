import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/update_status.dart';
import '../services/remote_config_service.dart';
import '../services/snooze_store.dart';
import '../utils/logger.dart';
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
    this.navigatorKey,
    this.iosAppId,
    this.androidPackageId,
    this.dialogBuilder,
    this.title,
    this.message,
    this.updateButtonText,
    this.laterButtonText,
    this.style,
    this.snoozeDuration = const Duration(days: 3),
    this.minimumFetchInterval = const Duration(hours: 1),
    this.enableInDebugMode = false,
    this.clearSnoozeInDebugMode = false,
    this.listenForRealtimeUpdates = true,
    this.enableLogging,
    @visibleForTesting RemoteConfigService? remoteConfigService,
    @visibleForTesting FlUpdaterSnoozeStore? snoozeStore,
  })  : _remoteConfigService = remoteConfigService,
        _snoozeStore = snoozeStore;

  /// The child widget to display (typically the app navigator or screen).
  final Widget child;

  /// An optional [GlobalKey<NavigatorState>] to explicitly identify the root [Navigator].
  ///
  /// When omitted, [FlUpdaterWrapper] automatically locates the [Navigator]
  /// descendant inside [child] (or in its ancestor tree).
  final GlobalKey<NavigatorState>? navigatorKey;

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
  /// Defaults to 1 hour.
  final Duration minimumFetchInterval;

  /// Whether to enable update checking in debug mode.
  ///
  /// Defaults to `false` so development hot restarts do not consume Remote Config
  /// quota or interrupt development flow.
  final bool enableInDebugMode;

  /// Whether to automatically clear any saved snooze state when running in debug mode.
  ///
  /// When `true` and running in debug mode, previous snoozes are cleared so update
  /// prompts are shown again without waiting for the snooze duration to expire.
  final bool clearSnoozeInDebugMode;

  /// Whether to listen to real-time Remote Config updates via [FirebaseRemoteConfig.onConfigUpdated].
  ///
  /// When `true`, whenever `fl_updater_latest_version` or `fl_updater_min_version` is updated
  /// in the Firebase Console, the new config is activated and evaluated immediately
  /// without waiting for [minimumFetchInterval]. Defaults to `true`.
  final bool listenForRealtimeUpdates;

  /// Whether to enable diagnostic logging.
  ///
  /// When null, defaults to [FlUpdaterLogger.enabled].
  final bool? enableLogging;

  final RemoteConfigService? _remoteConfigService;
  final FlUpdaterSnoozeStore? _snoozeStore;

  @override
  State<FlUpdaterWrapper> createState() => _FlUpdaterWrapperState();
}

class _FlUpdaterWrapperState extends State<FlUpdaterWrapper> {
  late final RemoteConfigService _remoteConfigService;
  late final FlUpdaterSnoozeStore _snoozeStore;
  StreamSubscription<RemoteConfigUpdate>? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _remoteConfigService = widget._remoteConfigService ?? RemoteConfigService();
    _snoozeStore = widget._snoozeStore ?? FlUpdaterSnoozeStore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
      _setupRealtimeListener();
    });
  }

  void _setupRealtimeListener() {
    if (!widget.listenForRealtimeUpdates) return;
    if (kDebugMode && !widget.enableInDebugMode) {
      FlUpdaterLogger.log(
        'Real-time Remote Config updates disabled in debug mode (set enableInDebugMode: true to test in debug).',
        enableLogging: widget.enableLogging,
      );
      return;
    }

    _realtimeSubscription?.cancel();
    _realtimeSubscription = _remoteConfigService.listenForUpdates(
      () async {
        FlUpdaterLogger.log(
          'Real-time Remote Config signal received: evaluating update status immediately.',
          enableLogging: widget.enableLogging,
        );
        if (mounted) {
          await _checkForUpdate(fromRealtime: true);
        }
      },
      enableLogging: widget.enableLogging,
    );
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  bool _isDialogShowing = false;

  Future<void> _checkForUpdate({bool fromRealtime = false}) async {
    if (!mounted) return;
    if (_isDialogShowing) {
      FlUpdaterLogger.log(
        'Update check skipped because update dialog is already showing.',
        enableLogging: widget.enableLogging,
      );
      return;
    }

    if (fromRealtime) {
      FlUpdaterLogger.log(
        'Real-time update received: clearing snooze store to show update immediately.',
        enableLogging: widget.enableLogging,
      );
      await _snoozeStore.clear();
    } else if (kDebugMode && widget.clearSnoozeInDebugMode) {
      FlUpdaterLogger.log(
        'clearSnoozeInDebugMode is enabled: clearing snooze store in debug mode.',
        enableLogging: widget.enableLogging,
      );
      await _snoozeStore.clear();
    }

    final info = fromRealtime
        ? await _remoteConfigService.evaluateActiveConfig(
            iosAppId: widget.iosAppId,
            androidPackageId: widget.androidPackageId,
            clearSnooze: true,
            enableLogging: widget.enableLogging,
          )
        : await _remoteConfigService.checkForUpdate(
            snoozeDuration: widget.snoozeDuration,
            minimumFetchInterval: widget.minimumFetchInterval,
            enableInDebugMode: widget.enableInDebugMode,
            enableLogging: widget.enableLogging,
            iosAppId: widget.iosAppId,
            androidPackageId: widget.androidPackageId,
          );

    if (!mounted) return;
    if (info.status == UpdateStatus.none) return;

    _isDialogShowing = true;
    try {
      await presentUpdateDialog(
        context,
        info: info,
        snoozeStore: _snoozeStore,
        snoozeDuration: widget.snoozeDuration,
        navigatorKey: widget.navigatorKey,
        dialogBuilder: widget.dialogBuilder,
        title: widget.title,
        message: widget.message,
        updateButtonText: widget.updateButtonText,
        laterButtonText: widget.laterButtonText,
        style: widget.style,
        enableLogging: widget.enableLogging,
      );
    } finally {
      _isDialogShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
