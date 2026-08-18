import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/fl_updater.dart';

void main() {
  setUp(() {
    FlUpdaterLogger.enabled = false;
  });

  tearDown(() {
    FlUpdaterLogger.enabled = false;
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

  test('FlUpdaterLogger.log executes safely when disabled and enabled', () {
    // Should not throw when disabled
    FlUpdaterLogger.enabled = false;
    expect(
      () => FlUpdaterLogger.log('test message', enableLogging: false),
      returnsNormally,
    );

    // Should not throw when enabled
    expect(
      () => FlUpdaterLogger.log(
        'test message with error',
        error: Exception('sample error'),
        stackTrace: StackTrace.current,
        enableLogging: true,
      ),
      returnsNormally,
    );
  });
}
