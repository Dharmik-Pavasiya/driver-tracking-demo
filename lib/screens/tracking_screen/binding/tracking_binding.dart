import 'package:get/get.dart';

import '../../../data/location_repository.dart';
import '../../../services/location_api.dart';
import '../../../services/location_service.dart';
import '../../../services/sync_service.dart';
import '../controller/tracking_controller.dart';

/// Connects the tracking screen to the app's existing services.
class TrackingBinding extends Bindings {
  /// Creates the controller when this screen opens, using existing services.
  @override
  void dependencies() => Get.lazyPut(
    () => TrackingController(
      repository: Get.find<LocationRepository>(),
      source: Get.find<LocationSource>(),
      api: Get.find<RestLocationApi>(),
      sync: Get.find<SyncService>(),
    ),
  );
}
