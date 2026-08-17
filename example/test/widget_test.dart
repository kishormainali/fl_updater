// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fl_updater_example/main.dart';

void main() {
  testWidgets('renders the app bar title and check-for-update button', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Verify the AppBar title and the manual-check button are present.
    // MyApp's FlUpdaterWrapper has enableInDebugMode: true, so this also
    // exercises the real RemoteConfigService.checkForUpdate() path — it
    // fails open (PackageInfo.fromPlatform()/FirebaseRemoteConfig.instance
    // throw with no test mocks registered) and completes safely with no
    // dialog shown.
    expect(find.text('fl_updater example'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Check for update'), findsOneWidget);
  });
}
