import 'package:get/get.dart';

import '../../../network/api_provider/location_api.dart';
import '../../../network/connectivity/network_connectivity.dart';
import '../controller/tracking_controller.dart';
import '../data/location_repository.dart';
import '../service/location_service.dart';
import '../service/sync_service.dart';

/// Creates the tracking controller when its screen opens.
class TrackingBinding extends Bindings {
  /// Injects dependencies explicitly so business logic is easy to test.
  @override
  void dependencies() {
    Get.lazyPut<TrackingController>(
      () => TrackingController(
        repository: Get.find<LocationRepository>(),
        source: Get.find<LocationSource>(),
        network: Get.find<NetworkConnectivity>(),
        api: Get.find<RestLocationApi>(),
        sync: Get.find<SyncService>(),
      ),
    );
  }
}
