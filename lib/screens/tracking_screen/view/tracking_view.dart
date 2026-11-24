import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/app_strings.dart';
import '../../../models/location_record.dart';
import '../../../services/location_api.dart';
import '../controller/tracking_controller.dart';

/// Plain widgets display GetX state; saving and uploading stay in their services.
class TrackingView extends GetView<TrackingController> {
  /// GetView obtains the controller registered by TrackingBinding.
  const TrackingView({super.key});

  /// Rebuilds the plain controls and recent points when their Rx values change.
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(AppStrings.title)),
    body: Obx(() {
      final sync = controller.sync;
      final point = controller.latest;
      final error = controller.errorMessage.value ?? sync.errorMessage.value;
      final busy = !sync.isReady.value || controller.isStarting.value;
      final buttonText = controller.isStarting.value
          ? AppStrings.permission
          : controller.isTracking.value
          ? AppStrings.stop
          : AppStrings.start;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(sync.connection.online ? AppStrings.online : AppStrings.offline),
          const SizedBox(height: 12),
          Text(
            controller.isTracking.value
                ? AppStrings.tracking
                : AppStrings.stopped,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            point == null
                ? AppStrings.noLocation
                : '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy
                ? null
                : () {
                    if (controller.isTracking.value) {
                      controller.stopTracking();
                    } else {
                      controller.startTracking();
                    }
                  },
            child: Text(buttonText),
          ),
          const SizedBox(height: 16),
          Text(AppStrings.counts(sync.pending, sync.synced, sync.blocked)),
          if (sync.isSyncing.value && sync.pending > 0)
            const Text(AppStrings.uploading),
          if (error != null)
            Text(error, style: const TextStyle(color: Colors.red)),
          const Divider(height: 32),
          const Text(AppStrings.demoControls),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(AppStrings.simulateLocation),
            subtitle: const Text(AppStrings.simulationHint),
            value: controller.simulateLocation.value,
            onChanged: busy || controller.isTracking.value
                ? null
                : controller.setLocationSimulation,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(AppStrings.simulateOffline),
            value: sync.connection.simulateOffline.value,
            onChanged: controller.setOfflineMode,
          ),
          DropdownButtonFormField<DemoFailure>(
            initialValue: controller.uploadFailure.value,
            decoration: const InputDecoration(labelText: AppStrings.mockApi),
            items: const [
              DropdownMenuItem(
                value: DemoFailure.none,
                child: Text(AppStrings.healthy),
              ),
              DropdownMenuItem(
                value: DemoFailure.beforeCommit,
                child: Text(AppStrings.failBefore),
              ),
              DropdownMenuItem(
                value: DemoFailure.afterCommit,
                child: Text(AppStrings.failAfter),
              ),
            ],
            onChanged: (value) {
              if (value != null) controller.setUploadFailure(value);
            },
          ),
          TextButton(
            onPressed: sync.isSyncing.value ? null : sync.retryNow,
            child: const Text(AppStrings.retry),
          ),
          const Divider(height: 24),
          const Text(AppStrings.recent),
          if (sync.records.isEmpty) const Text(AppStrings.empty),
          ...sync.records
              .take(10)
              .map(
                (row) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${row.latitude.toStringAsFixed(6)}, ${row.longitude.toStringAsFixed(6)}',
                  ),
                  subtitle: Text(
                    '${row.capturedAt.toLocal().toString().split('.').first}\n${row.attempts} attempts',
                  ),
                  trailing: Text(
                    row.status.name,
                    style: TextStyle(
                      color: row.status == UploadStatus.synced
                          ? Colors.green
                          : null,
                    ),
                  ),
                  isThreeLine: true,
                ),
              ),
        ],
      );
    }),
  );
}
