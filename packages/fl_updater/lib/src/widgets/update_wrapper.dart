import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:fp_logger/fp_logger.dart';

import '../models/update_status.dart';
import '../services/remote_config_service.dart';
import '../services/snooze_store.dart';
import '../utils/logging.dart';
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
    this.flavor = appFlavor,
    this.platform,
    this.dialogBuilder,
    this.title,
    this.message,
    this.updateButtonText,
    this.laterButtonText,
    this.style,
    this.snoozeDuration = const Duration(days: 3),
    this.minimumFetchInterval = const Duration(hours: 1),
    this.enabled = !kDebugMode,
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

  /// The build flavor to scope the `fl_updater_config` Remote Config parameter to,
  /// e.g. `'staging'`.
  ///
  /// The `fl_updater_config` parameter's value is a JSON object with top-level
  /// `min_version` / `latest_version` fields and optional `flavors` / `platforms`
  /// maps for overriding them — see [platform] for the full shape and the
  /// resolution order between the two.
  ///
  /// Defaults to Flutter's built-in [appFlavor] (the value passed to `--flavor` at
  /// build time), so most apps don't need to pass this explicitly.
  final String? flavor;

  /// The platform to scope the `fl_updater_config` Remote Config parameter to,
  /// e.g. `'android'` or `'ios'`.
  ///
  /// The `fl_updater_config` parameter's value is a JSON object shaped like:
  /// ```json
  /// {
  ///   "min_version": "1.0.0",
  ///   "latest_version": "1.0.0",
  ///   "flavors": {
  ///     "staging": { "min_version": "1.1.0", "latest_version": "1.1.0" }
  ///   },
  ///   "platforms": {
  ///     "android": {
  ///       "min_version": "1.0.1",
  ///       "latest_version": "1.0.1",
  ///       "flavors": {
  ///         "staging": { "min_version": "1.1.1", "latest_version": "1.1.1" }
  ///       }
  ///     }
  ///   }
  /// }
  /// ```
  /// `min_version` and `latest_version` are each resolved independently, most
  /// specific first: `platforms[platform].flavors[flavor]`, then
  /// `platforms[platform]`, then `flavors[flavor]`, then the top-level field.
  /// Any of these can be omitted — a scope only needs to set the fields it
  /// actually wants to override.
  ///
  /// Defaults to the current platform (`'android'` / `'ios'`, detected via
  /// [defaultTargetPlatform]; `null` — no platform-scoped override — on other
  /// platforms), so most apps don't need to pass this explicitly.
  final String? platform;

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

  /// Global gate for automatic update checking (both the initial check and
  /// real-time listening).
  ///
  /// Defaults to `!kDebugMode`, so update checks run in release builds and
  /// are skipped in debug builds, avoiding wasted Remote Config quota and
  /// interrupted development flow during hot restarts. Pass `true` explicitly
  /// to test update checks in debug mode, or `false` to disable checking
  /// entirely regardless of build mode.
  final bool enabled;

  /// Whether to automatically clear any saved snooze state when running in debug mode.
  ///
  /// When `true` and running in debug mode, previous snoozes are cleared so update
  /// prompts are shown again without waiting for the snooze duration to expire.
  /// Only takes effect when [enabled] is also `true`.
  final bool clearSnoozeInDebugMode;

  /// Whether to listen to real-time Remote Config updates via [FirebaseRemoteConfig.onConfigUpdated].
  ///
  /// When `true`, whenever the `fl_updater_config` parameter is updated in the
  /// Firebase Console, the new config is activated and evaluated immediately
  /// without waiting for [minimumFetchInterval]. Defaults to `true`.
  final bool listenForRealtimeUpdates;

  /// Whether to enable diagnostic logging.
  ///
  /// When null, defaults to `FlUpdater.enableLogging`.
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
    // `enabled` is the master gate and takes precedence over every other
    // parameter (enableLogging, listenForRealtimeUpdates) — checked first,
    // before any of them are acted on. Also tears down any existing
    // subscription, so toggling `enabled` off at runtime (via a rebuild)
    // reliably stops real-time listening rather than leaving it running.
    if (!widget.enabled) {
      _realtimeSubscription?.cancel();
      _realtimeSubscription = null;
      if (widget.enableLogging ?? flUpdaterLoggingEnabled) {
        Logger.i(
          'Real-time Remote Config updates disabled (enabled is false; set enabled: true to test in debug).',
          tag: flUpdaterLogTag,
        );
      }
      return;
    }
    if (!widget.listenForRealtimeUpdates) {
      _realtimeSubscription?.cancel();
      _realtimeSubscription = null;
      return;
    }

    _realtimeSubscription?.cancel();
    _realtimeSubscription = _remoteConfigService.listenForUpdates(
      () async {
        if (mounted) {
          await _checkForUpdate(fromRealtime: true);
        }
      },
      enableLogging: widget.enableLogging,
    );
  }

  @override
  void didUpdateWidget(covariant FlUpdaterWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled ||
        widget.listenForRealtimeUpdates != oldWidget.listenForRealtimeUpdates) {
      _setupRealtimeListener();
    }
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  bool _isDialogShowing = false;

  Future<void> _checkForUpdate({bool fromRealtime = false}) async {
    if (!mounted) return;

    // `enabled` is the master gate and takes precedence over every other
    // parameter (enableLogging, clearSnoozeInDebugMode) — checked first,
    // before any of them are acted on.
    final logging = widget.enableLogging ?? flUpdaterLoggingEnabled;
    if (!widget.enabled) {
      if (logging) {
        Logger.i('Update check skipped (enabled is false).',
            tag: flUpdaterLogTag);
      }
      return;
    }

    if (_isDialogShowing) {
      if (logging) {
        Logger.i(
          'Update check skipped because update dialog is already showing.',
          tag: flUpdaterLogTag,
        );
      }
      return;
    }

    if (fromRealtime) {
      if (logging) {
        Logger.i(
          'Real-time update received: clearing snooze store to show update immediately.',
          tag: flUpdaterLogTag,
        );
      }
      await _snoozeStore.clear();
    } else if (kDebugMode && widget.clearSnoozeInDebugMode) {
      if (logging) {
        Logger.i(
          'clearSnoozeInDebugMode is enabled: clearing snooze store in debug mode.',
          tag: flUpdaterLogTag,
        );
      }
      await _snoozeStore.clear();
    }

    final info = fromRealtime
        ? await _remoteConfigService.evaluateActiveConfig(
            iosAppId: widget.iosAppId,
            androidPackageId: widget.androidPackageId,
            clearSnooze: true,
            enableLogging: widget.enableLogging,
            flavor: widget.flavor,
            platform: widget.platform,
          )
        : await _remoteConfigService.checkForUpdate(
            snoozeDuration: widget.snoozeDuration,
            minimumFetchInterval: widget.minimumFetchInterval,
            enabled: widget.enabled,
            enableLogging: widget.enableLogging,
            iosAppId: widget.iosAppId,
            androidPackageId: widget.androidPackageId,
            flavor: widget.flavor,
            platform: widget.platform,
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
