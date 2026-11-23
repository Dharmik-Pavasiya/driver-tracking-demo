import 'package:get/get.dart';

import '../screens/tracking_screen/binding/tracking_binding.dart';
import '../screens/tracking_screen/view/tracking_view.dart';
import 'app_routes.dart';

/// Connects the route to its view and controller binding.
abstract final class AppPages {
  static final pages = <GetPage>[
    GetPage(
      name: AppRoutes.tracking,
      page: () => const TrackingView(),
      binding: TrackingBinding(),
    ),
  ];
}
