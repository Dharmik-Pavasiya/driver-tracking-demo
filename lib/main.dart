import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app/app_binding.dart';
import 'router/app_pages.dart';
import 'router/app_routes.dart';
import 'screens/tracking_screen/data/database_factory.dart';
import 'screens/tracking_screen/data/location_repository.dart';

/// Opens SQLite before the screen appears so every GPS fix can be saved first.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = LocationRepository(await openOutboxDatabase());
    await repository.initialize();
    runApp(DriverTrackingApp(repository: repository));
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to open local storage. Restart the app.\n$error',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Defines the standard mobile theme, shared bindings and GetX routes.
class DriverTrackingApp extends StatelessWidget {
  /// Receives the ready repository instead of opening a database in the view.
  const DriverTrackingApp({super.key, required this.repository});
  final LocationRepository repository;

  /// Builds a Material application containing the tracking screen.
  @override
  Widget build(BuildContext context) => GetMaterialApp(
    title: 'Driver Location',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      scaffoldBackgroundColor: Colors.white,
    ),
    initialBinding: AppBinding(repository),
    initialRoute: AppRoutes.tracking,
    getPages: AppPages.pages,
  );
}
