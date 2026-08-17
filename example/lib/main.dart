import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_updater/fl_updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (error) {
    // No Firebase project is configured for this example yet. Run
    // `flutterfire configure` from the example/ directory to enable
    // real Remote Config values — fl_updater fails open without it,
    // so the app still runs, it just never finds an update.
    debugPrint('Firebase.initializeApp failed: $error');
  }
  runApp(const MyApp());
}

// Set these to your app's real identifiers before shipping — the Play
// Store package id and the numeric App Store id. Neither comes from
// Remote Config; the wrapper takes them directly. Leaving androidPackageId
// null falls back to the host app's own package name on Android; iOS has
// no such fallback and needs a real numeric id to open the App Store.
const _androidPackageId = 'com.kishormainali.fl_updater_example';
const _iosAppId = '000000000';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) => FlUpdaterWrapper(
        iosAppId: _iosAppId,
        androidPackageId: _androidPackageId,
        // This example app is specifically for exercising fl_updater during
        // development, so it opts back into fetching while debugging. A real
        // app normally leaves this false (the default) to avoid Remote
        // Config fetches and surprise dialogs on every debug hot restart.
        enableInDebugMode: true,
        child: child!,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _checkManually(BuildContext context) async {
    final updater = FlUpdater();
    await updater.showUpdateDialog(
      context,
      iosAppId: _iosAppId,
      androidPackageId: _androidPackageId,
      enableInDebugMode: true,
      style: const FlUpdaterDialogStyle(
        titleStyle: TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('fl_updater example')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _checkManually(context),
          child: const Text('Check for update'),
        ),
      ),
    );
  }
}
