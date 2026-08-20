import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_updater/fl_updater.dart';
import 'package:fl_updater/src/utils/logging.dart';

/// Captures stdout writes made via `print()` — what `package:fp_logger`
/// emits through internally — by running [body] inside a zone with a
/// custom print handler.
Future<List<String>> _captureLogs(FutureOr<void> Function() body) async {
  final logs = <String>[];
  await runZoned(
    () async => await body(),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => logs.add(line),
    ),
  );
  return logs;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    flUpdaterLoggingEnabled = false;
  });
  tearDown(() => flUpdaterLoggingEnabled = false);

  test('FlUpdater.enableLogging is false by default', () {
    expect(FlUpdater.enableLogging, isFalse);
    expect(flUpdaterLoggingEnabled, isFalse);
  });

  test(
      'FlUpdater.enableLogging getter and setter mirror flUpdaterLoggingEnabled',
      () {
    FlUpdater.enableLogging = true;
    expect(flUpdaterLoggingEnabled, isTrue);
    expect(FlUpdater.enableLogging, isTrue);

    FlUpdater.enableLogging = false;
    expect(flUpdaterLoggingEnabled, isFalse);
    expect(FlUpdater.enableLogging, isFalse);
  });

  test('FlUpdater.clearSnoozeStore prints nothing when logging is disabled',
      () async {
    final logs = await _captureLogs(() async {
      await FlUpdater.clearSnoozeStore();
    });

    expect(logs, isEmpty);
  });

  test(
      'FlUpdater.clearSnoozeStore prints a tagged message when logging is enabled',
      () async {
    FlUpdater.enableLogging = true;

    final logs = await _captureLogs(() async {
      await FlUpdater.clearSnoozeStore();
    });

    expect(logs, isNotEmpty);
    expect(logs.join('\n'), contains('[fl_updater]'));
    expect(logs.join('\n'), contains('Clearing snooze store globally.'));
  });

  test('FlUpdater.clearSnooze respects a per-instance enableLogging override',
      () async {
    final updater = FlUpdater(enableLogging: true);

    final logs = await _captureLogs(() async {
      await updater.clearSnooze();
    });

    expect(logs, isNotEmpty);
    expect(logs.join('\n'), contains('Clearing snooze store.'));
  });
}
