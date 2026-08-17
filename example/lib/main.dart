import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_updater/fl_updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (error) {
    // If Firebase isn't configured yet, fl_updater fails open safely.
    // To connect to a live Firebase project, run `flutterfire configure` inside the example/ directory.
    debugPrint('Firebase.initializeApp notice: $error');
  }
  runApp(const ExampleApp());
}

// Replace with your real identifiers:
// - On iOS, the numeric App Store ID (e.g. '123456789') is required.
// - On Android, the package ID defaults to the host application if omitted.
const _iosAppId = '123456789';
const _androidPackageId = 'com.kishormainali.fl_updater_example';

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fl_updater Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // FlUpdaterWrapper automatically evaluates update status on launch
      builder: (context, child) => FlUpdaterWrapper(
        iosAppId: _iosAppId,
        androidPackageId: _androidPackageId,
        // enableInDebugMode is true here for example/testing purposes.
        // In production apps, leave this false to avoid consuming Remote Config quota during development.
        enableInDebugMode: true,
        child: child!,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _updater = FlUpdater();
  UpdateInfo? _lastCheckedInfo;
  bool _isLoading = false;

  Future<void> _checkManually() async {
    setState(() => _isLoading = true);
    try {
      final info = await _updater.checkForUpdate(
        iosAppId: _iosAppId,
        androidPackageId: _androidPackageId,
        enableInDebugMode: true,
      );
      setState(() => _lastCheckedInfo = info);
      if (mounted) {
        await _updater.showUpdateDialog(
          context,
          info: info,
          iosAppId: _iosAppId,
          androidPackageId: _androidPackageId,
          enableInDebugMode: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showStyledDialog() async {
    await _updater.showUpdateDialog(
      context,
      iosAppId: _iosAppId,
      androidPackageId: _androidPackageId,
      enableInDebugMode: true,
      title: '🚀 Major Update Available!',
      message: 'A brand-new version is ready with exciting features and enhancements.',
      updateButtonText: 'Upgrade Now',
      laterButtonText: 'Remind Me Later',
      style: FlUpdaterDialogStyle(
        backgroundColor: Colors.deepPurple.shade50,
        titleStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple,
          fontSize: 20,
        ),
        messageStyle: const TextStyle(color: Colors.black87, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.rocket_launch, size: 40, color: Colors.deepPurple),
      ),
    );
  }

  Future<void> _showCustomBuilderDialog() async {
    await _updater.showUpdateDialog(
      context,
      iosAppId: _iosAppId,
      androidPackageId: _androidPackageId,
      enableInDebugMode: true,
      dialogBuilder: (dialogContext, info, onUpdate, onLater) {
        final isForce = info.status == UpdateStatus.force;
        return AlertDialog(
          icon: const Icon(Icons.stars, color: Colors.amber, size: 36),
          title: Text('Custom Dialog: ${info.latestVersion}'),
          content: Text(
            'Current version is ${info.currentVersion}.\n\n'
            'This dialog was rendered using a custom dialogBuilder callback.',
          ),
          actions: [
            if (!isForce)
              TextButton(
                onPressed: onLater,
                child: const Text('Dismiss & Snooze'),
              ),
            FilledButton.icon(
              onPressed: onUpdate,
              icon: const Icon(Icons.download),
              label: const Text('Download Update'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('fl_updater Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Firebase Remote Config Integration',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Set the following keys in your Firebase Remote Config Console:\n'
                      '• fl_updater_latest_version (e.g. "2.0.0")\n'
                      '• fl_updater_min_version (e.g. "1.5.0")',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_lastCheckedInfo != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last Evaluation Result',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Divider(),
                      Text('Current Version: ${_lastCheckedInfo!.currentVersion}'),
                      Text('Latest Version: ${_lastCheckedInfo!.latestVersion}'),
                      Text('Status: ${_lastCheckedInfo!.status.name}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            FilledButton.icon(
              onPressed: _isLoading ? null : _checkManually,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('Check for Update (Default Dialog)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _showStyledDialog,
              icon: const Icon(Icons.palette),
              label: const Text('Show Styled Dialog Demo'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _showCustomBuilderDialog,
              icon: const Icon(Icons.dashboard_customize),
              label: const Text('Show Custom Builder Dialog Demo'),
            ),
          ],
        ),
      ),
    );
  }
}
