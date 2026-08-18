import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fl_updater_example/main.dart';

void main() {
  testWidgets('renders the app bar title and action buttons',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('fl_updater Example'), findsOneWidget);
    expect(
        find.widgetWithText(FilledButton, 'Check for Update (Default Dialog)'),
        findsOneWidget);
  });
}
