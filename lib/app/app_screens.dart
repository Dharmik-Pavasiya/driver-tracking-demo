import 'package:get/get.dart';

import '../screens/tracking_screen/binding/tracking_binding.dart';
import '../screens/tracking_screen/view/tracking_view.dart';

/// All route names, screen builders and bindings are registered together here.
abstract final class AppScreens {
  static const tracking = '/tracking';
  static final pages = <GetPage>[
    GetPage(
      name: tracking,
      page: () => const TrackingView(),
      binding: TrackingBinding(),
    ),
  ];
}
