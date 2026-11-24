import 'dart:async';

import 'package:get/get.dart';

import '../data/location_repository.dart';
import '../services/connectivity_service.dart';
import '../services/location_api.dart';
import '../services/location_service.dart';
import '../services/mock_api_service.dart';
import '../services/sync_service.dart';

/// Creates shared services once; screen bindings only create screen controllers.
class AppBinding extends Bindings {
  /// Reuses startup resources instead of opening a second database or mock.
  AppBinding(this.repository, this.mock, this.apiUrl);
  final LocationRepository repository;
  final MockApiService mock;
  final String apiUrl;

  /// Registers shared dependencies for use by any screen binding.
  @override
  void dependencies() {
    Get.put(repository, permanent: true);
    Get.put(mock, permanent: true);
    final connection = Get.put(ConnectivityService(), permanent: true);
    final api = Get.put(RestLocationApi(baseUrl: apiUrl), permanent: true);
    Get.put<LocationSource>(DeviceLocationService(), permanent: true);
    final sync = Get.put(
      SyncService(repository: repository, api: api, connection: connection),
      permanent: true,
    );
    unawaited(sync.startAutomaticSync());
  }
}
