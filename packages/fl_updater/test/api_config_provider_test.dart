import 'package:fl_updater/fl_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fetch returns the callback value and current() returns it afterwards',
      () async {
    final provider = ApiConfigProvider(fetch: () async => '{"a":1}');
    expect(await provider.current(), isNull);
    expect(await provider.fetch(), '{"a":1}');
    expect(await provider.current(), '{"a":1}');
  });

  test('fetch rethrows callback errors but keeps the last cached value',
      () async {
    var fail = false;
    final provider = ApiConfigProvider(fetch: () async {
      if (fail) throw Exception('boom');
      return '{"a":1}';
    });
    await provider.fetch();
    fail = true;
    await expectLater(provider.fetch(), throwsException);
    expect(await provider.current(), '{"a":1}');
  });

  test('changes is null (no push support)', () {
    expect(ApiConfigProvider(fetch: () async => '').changes, isNull);
  });
}
