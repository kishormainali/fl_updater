// test/update_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_updater/src/models/update_info.model.dart';
import 'package:fl_updater/src/models/update_status.dart';
import 'package:fl_updater/src/update_dialog.dart';

void main() {
  const softInfo = UpdateInfo(
    currentVersion: '1.0.0',
    latestVersion: '1.1.0',
    status: UpdateStatus.soft,
  );

  const forceInfo = UpdateInfo(
    currentVersion: '1.0.0',
    latestVersion: '2.0.0',
    status: UpdateStatus.force,
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    required UpdateInfo info,
    required VoidCallback onUpdate,
    required VoidCallback onLater,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FlUpdaterDialog(
              info: info,
              onUpdate: onUpdate,
              onLater: onLater,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('soft update shows Later button and calls callbacks', (tester) async {
    var updateTapped = false;
    var laterTapped = false;

    await pumpDialog(
      tester,
      info: softInfo,
      onUpdate: () => updateTapped = true,
      onLater: () => laterTapped = true,
    );

    expect(find.byKey(const Key('fl_updater_later_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('fl_updater_later_button')));
    await tester.pump();
    expect(laterTapped, isTrue);

    await tester.tap(find.byKey(const Key('fl_updater_update_button')));
    await tester.pump();
    expect(updateTapped, isTrue);
  });

  testWidgets('force update hides Later button', (tester) async {
    await pumpDialog(
      tester,
      info: forceInfo,
      onUpdate: () {},
      onLater: () {},
    );

    expect(find.byKey(const Key('fl_updater_later_button')), findsNothing);
    expect(find.byKey(const Key('fl_updater_update_button')), findsOneWidget);
  });

  testWidgets('custom title, message and button text are used', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FlUpdaterDialog(
              info: softInfo,
              onUpdate: () {},
              onLater: () {},
              title: 'Custom title',
              message: 'Custom message',
              updateButtonText: 'Go',
              laterButtonText: 'Nope',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Custom title'), findsOneWidget);
    expect(find.text('Custom message'), findsOneWidget);
    expect(find.text('Go'), findsOneWidget);
    expect(find.text('Nope'), findsOneWidget);
  });
}
