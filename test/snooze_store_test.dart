import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_updater/src/services/snooze_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('isSnoozed is false when nothing has been snoozed', () async {
    final store = FlUpdaterSnoozeStore();
    expect(await store.isSnoozed('1.0.0'), isFalse);
  });

  test('isSnoozed is true for the snoozed version within the duration', () async {
    final store = FlUpdaterSnoozeStore();
    await store.snooze('1.2.0', const Duration(days: 3));

    expect(await store.isSnoozed('1.2.0'), isTrue);
  });

  test('isSnoozed is false for a different version', () async {
    final store = FlUpdaterSnoozeStore();
    await store.snooze('1.2.0', const Duration(days: 3));

    expect(await store.isSnoozed('1.3.0'), isFalse);
  });

  test('isSnoozed is false once the duration has elapsed', () async {
    final store = FlUpdaterSnoozeStore();
    await store.snooze('1.2.0', const Duration(seconds: -1));

    expect(await store.isSnoozed('1.2.0'), isFalse);
  });

  test('clear removes the snoozed state', () async {
    final store = FlUpdaterSnoozeStore();
    await store.snooze('1.2.0', const Duration(days: 3));
    await store.clear();

    expect(await store.isSnoozed('1.2.0'), isFalse);
  });
}
