import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../network/api_provider/location_api.dart';
import '../controller/tracking_controller.dart';
import '../data/location_record.dart';

/// One plain mobile screen: current fix, controls, counts and recent locations.
/// GetView retrieves the bound controller; Obx rebuilds when its Rx fields change.
class TrackingView extends GetView<TrackingController> {
  /// Creates the tracking route's view without owning services or business logic.
  const TrackingView({super.key});

  /// Builds standard Material controls; no maps, illustrations or dashboard cards.
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Driver Location')),
    body: Obx(() {
      final latest = controller.latest;
      final error = controller.errorMessage.value;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            controller.network.online ? 'Network: online' : 'Network: offline',
          ),
          const SizedBox(height: 12),
          Text(
            controller.isTracking.value
                ? 'Tracking active'
                : 'Tracking stopped',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            latest == null
                ? 'No location captured yet.'
                : '${latest.latitude.toStringAsFixed(6)}, ${latest.longitude.toStringAsFixed(6)}',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: !controller.isReady.value || controller.isStarting.value
                ? null
                : controller.isTracking.value
                ? controller.stopTracking
                : controller.startTracking,
            child: Text(
              controller.isStarting.value
                  ? 'Requesting permission…'
                  : controller.isTracking.value
                  ? 'Stop tracking'
                  : 'Start tracking',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Pending: ${controller.pending}   Synced: ${controller.synced}   Blocked: ${controller.blocked}',
          ),
          if (controller.isSyncing.value)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Uploading locations…'),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error, style: const TextStyle(color: Colors.red)),
            ),
          const Divider(height: 32),
          const Text('Demo controls'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Simulate offline'),
            value: controller.network.simulateOffline.value,
            onChanged: controller.network.setSimulateOffline,
          ),
          DropdownButtonFormField<DemoFailure>(
            initialValue: controller.uploadFailure.value,
            decoration: const InputDecoration(labelText: 'Mock API'),
            items: const [
              DropdownMenuItem(value: DemoFailure.none, child: Text('Healthy')),
              DropdownMenuItem(
                value: DemoFailure.beforeCommit,
                child: Text('Fail before saving'),
              ),
              DropdownMenuItem(
                value: DemoFailure.afterCommit,
                child: Text('Fail after saving'),
              ),
            ],
            onChanged: (value) {
              if (value != null) controller.setUploadFailure(value);
            },
          ),
          TextButton(
            onPressed: controller.network.online && !controller.isSyncing.value
                ? controller.retryNow
                : null,
            child: const Text('Retry pending uploads'),
          ),
          const Divider(height: 24),
          const Text('Recent locations'),
          if (controller.records.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Saved points will appear here.'),
            ),
          ...controller.records
              .take(10)
              .map(
                (row) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${row.latitude.toStringAsFixed(6)}, ${row.longitude.toStringAsFixed(6)}',
                  ),
                  subtitle: Text(
                    '${row.capturedAt.toLocal().toString().split('.').first}\n'
                    '${row.attempts} attempts${row.lastError == null ? '' : ' • ${row.lastError}'}',
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
