import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app/app_binding.dart';
import 'app/app_screens.dart';
import 'app/app_strings.dart';
import 'data/database_factory.dart';
import 'data/location_repository.dart';
import 'services/mock_api_service.dart';

/// Opens storage and starts the phone's mock automatically before showing the UI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = LocationRepository(await openOutboxDatabase());
    await repository.initialize();
    final mock = MockApiService(repository);
    final apiUrl = await mock.start();
    runApp(
      DriverTrackingApp(repository: repository, mock: mock, apiUrl: apiUrl),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Unable to start the app: $error')),
        ),
      ),
    );
  }
}

/// The shared screen registry is the only place that supplies routes to the app.
class DriverTrackingApp extends StatelessWidget {
  /// Receives the database and already-started mock from main.
  const DriverTrackingApp({
    super.key,
    required this.repository,
    required this.mock,
    required this.apiUrl,
  });
  final LocationRepository repository;
  final MockApiService mock;
  final String apiUrl;

  /// Configures the standard Material theme and centrally registered screens.
  @override
  Widget build(BuildContext context) => GetMaterialApp(
    title: AppStrings.title,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      scaffoldBackgroundColor: Colors.white,
    ),
    initialBinding: AppBinding(repository, mock, apiUrl),
    initialRoute: AppScreens.tracking,
    getPages: AppScreens.pages,
  );
}
