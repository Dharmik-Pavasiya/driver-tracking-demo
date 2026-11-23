import 'dart:async';

import 'package:flutter/material.dart';

import 'data/database_factory.dart';
import 'data/location_repository.dart';
import 'presentation/tracking_controller.dart';
import 'presentation/tracking_screen.dart';
import 'services/location_api.dart';
import 'services/location_source.dart';
import 'services/network_monitor.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = LocationRepository(await openOutboxDatabase());
    final network = NetworkMonitor();
    final api = RestLocationApi(
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://localhost:8081',
      ),
    );
    final sync = SyncService(
      repository: repository,
      api: api,
      isOnline: () => network.online,
    );
    final controller = TrackingController(
      repository: repository,
      source: SimulatedLocationSource(),
      network: network,
      api: api,
      sync: sync,
    );
    runApp(DriverTrackingApp(controller: controller));
    unawaited(controller.initialize());
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText('Could not open local storage.\n$error'),
            ),
          ),
        ),
      ),
    );
  }
}

class DriverTrackingApp extends StatefulWidget {
  const DriverTrackingApp({super.key, required this.controller});
  final TrackingController controller;
  @override
  State<DriverTrackingApp> createState() => _DriverTrackingAppState();
}

class _DriverTrackingAppState extends State<DriverTrackingApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.network.refresh());
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Driver tracking demo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF146B52)),
      scaffoldBackgroundColor: const Color(0xFFF4F6F5),
      cardTheme: const CardThemeData(elevation: 0, color: Colors.white),
    ),
    home: TrackingScreen(controller: widget.controller),
  );
}
