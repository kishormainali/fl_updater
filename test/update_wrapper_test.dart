import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_updater/fl_updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders child and shows no dialog when debug-gated (default enableInDebugMode)', (
    tester,
  ) async {
    // flutter test always runs in debug mode, so kDebugMode is true here.
    // With the default enableInDebugMode: false, RemoteConfigService's
    // debug gate returns before touching any platform channel or Firebase
    // instance — mirroring the pattern already proven safe in
    // test/fl_updater_test.dart.
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FlUpdaterWrapper(child: child!),
        home: const Scaffold(body: Text('child content')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('child content'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
