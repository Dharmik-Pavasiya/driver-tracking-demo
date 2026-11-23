import 'dart:io';

import 'package:get/get.dart';

import '../network/api_provider/location_api.dart';
import '../network/connectivity/network_connectivity.dart';
import '../screens/tracking_screen/data/location_repository.dart';
import '../screens/tracking_screen/service/location_service.dart';
import '../screens/tracking_screen/service/sync_service.dart';

/// Registers shared dependencies, following the supplied GetX template.
class AppBinding extends Bindings {
  /// Accepts the database repository initialized by main.
  AppBinding(this.repository);
  final LocationRepository repository;

  /// Creates one network listener, API client, native GPS adapter and sync worker.
  @override
  void dependencies() {
    Get.put<LocationRepository>(repository, permanent: true);
    Get.put<NetworkConnectivity>(NetworkConnectivity(), permanent: true);
    final configuredUrl = const String.fromEnvironment('API_BASE_URL');
    final defaultUrl = Platform.isAndroid
        ? 'http://10.0.2.2:8081'
        : 'http://localhost:8081';
    Get.put<RestLocationApi>(
      RestLocationApi(
        baseUrl: configuredUrl.isEmpty ? defaultUrl : configuredUrl,
      ),
      permanent: true,
    );
    Get.put<LocationSource>(DeviceLocationService(), permanent: true);
    Get.put<SyncService>(
      SyncService(
        repository: repository,
        api: Get.find<RestLocationApi>(),
        isOnline: () => Get.find<NetworkConnectivity>().online,
      ),
      permanent: true,
    );
  }
}
