import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/fl_updater.dart';

void main() {
  final originalDebugPrint = debugPrint;
  final capturedLogs = <String>[];

  setUp(() {
    FlUpdaterLogger.enabled = false;
    capturedLogs.clear();
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) capturedLogs.add(message);
    };
  });

  tearDown(() {
    FlUpdaterLogger.enabled = false;
    debugPrint = originalDebugPrint;
  });

  test('FlUpdaterLogger.enabled is false by default', () {
    expect(FlUpdaterLogger.enabled, isFalse);
    expect(FlUpdater.enableLogging, isFalse);
  });

  test(
      'FlUpdater.enableLogging getter and setter update FlUpdaterLogger.enabled',
      () {
    FlUpdater.enableLogging = true;
    expect(FlUpdaterLogger.enabled, isTrue);
    expect(FlUpdater.enableLogging, isTrue);

    FlUpdater.enableLogging = false;
    expect(FlUpdaterLogger.enabled, isFalse);
    expect(FlUpdater.enableLogging, isFalse);
  });

  test('FlUpdaterLogger.log executes safely and prints when enabled', () {
    // Should not print or throw when disabled
    FlUpdaterLogger.enabled = false;
    FlUpdaterLogger.log('test disabled message', enableLogging: false);
    expect(capturedLogs, isEmpty);

    // Should print formatted message when enabled
    FlUpdaterLogger.log('test enabled message', enableLogging: true);
    expect(capturedLogs.length, 1);
    expect(capturedLogs.first, contains('[fl_updater] test enabled message'));

    // Should include error and stackTrace when provided
    FlUpdaterLogger.log(
      'test error message',
      error: Exception('sample error'),
      stackTrace: StackTrace.fromString('custom_stack_trace_line'),
      enableLogging: true,
    );
    expect(capturedLogs.length, 2);
    expect(capturedLogs[1], contains('[fl_updater] test error message'));
    expect(capturedLogs[1], contains('Error: Exception: sample error'));
    expect(capturedLogs[1], contains('custom_stack_trace_line'));
  });
}
