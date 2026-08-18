import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';

/// Diagnostic logging utility for `fl_updater`.
///
/// Logging is disabled (`false`) by default so it does not clutter production or
/// debug logs. You can enable it globally via [enabled] (or [FlUpdater.enableLogging]),
/// or per-operation using the `enableLogging` parameter.
class FlUpdaterLogger {
  FlUpdaterLogger._();

  /// Global switch to enable or disable `fl_updater` logs.
  ///
  /// Defaults to `false`.
  static bool enabled = false;

  /// Emits a log message if logging is enabled globally or via [enableLogging].
  static void log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool? enableLogging,
  }) {
    final shouldLog = enableLogging ?? enabled;
    if (!shouldLog) return;

    final buffer = StringBuffer('[fl_updater] $message');
    if (error != null) {
      buffer.write(' | Error: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    debugPrint(buffer.toString());
    dev.log(
      message,
      name: 'fl_updater',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
