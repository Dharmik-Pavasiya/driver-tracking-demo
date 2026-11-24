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

  /// Assembles the screen; individual widget methods observe their own state.
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: _buildAppBar(), body: _buildBody(context));

  /// The title stays outside reactive builders because it does not change.
  PreferredSizeWidget _buildAppBar() =>
      AppBar(title: const Text(AppStrings.title));

  /// Keeps layout static while the small Obx children update independently.
  Widget _buildBody(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _buildConnectionStatus(),
      const SizedBox(height: 12),
      _buildTrackingStatus(context),
      const SizedBox(height: 8),
      _buildLatestLocation(),
      const SizedBox(height: 16),
      _buildTrackingButton(),
      const SizedBox(height: 16),
      _buildUploadCounts(),
      _buildSyncStatus(),
      _buildErrorMessage(),
      const Divider(height: 32),
      const Text(AppStrings.demoControls),
      _buildSimulationSwitch(),
      _buildOfflineSwitch(),
      _buildMockApiDropdown(),
      _buildRetryButton(),
      const Divider(height: 24),
      const Text(AppStrings.recent),
      _buildRecentLocations(),
    ],
  );

  /// Only this label observes internet availability and the offline override.
  Widget _buildConnectionStatus() => Obx(
    () => Text(
      controller.sync.connection.online
          ? AppStrings.online
          : AppStrings.offline,
    ),
  );

  /// The active/stopped label only needs the tracking flag.
  Widget _buildTrackingStatus(BuildContext context) => Obx(
    () => Text(
      controller.isTracking.value ? AppStrings.tracking : AppStrings.stopped,
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );

  /// Saved-record changes refresh coordinates without rebuilding the controls.
  Widget _buildLatestLocation() => Obx(() {
    final point = controller.latest;
    return Text(
      point == null
          ? AppStrings.noLocation
          : '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
    );
  });

  /// Readiness, permission preparation and tracking state affect this button.
  Widget _buildTrackingButton() => Obx(() {
    final busy = !controller.sync.isReady.value || controller.isStarting.value;
    final buttonText = controller.isStarting.value
        ? AppStrings.permission
        : controller.isTracking.value
        ? AppStrings.stop
        : AppStrings.start;
    return FilledButton(
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
    );
  });

  /// Counts derive from saved rows, so only this summary observes those rows.
  Widget _buildUploadCounts() => Obx(() {
    final sync = controller.sync;
    return Text(AppStrings.counts(sync.pending, sync.synced, sync.blocked));
  });

  /// Shows upload progress without refreshing the rest of the screen.
  Widget _buildSyncStatus() => Obx(() {
    final sync = controller.sync;
    return sync.isSyncing.value && sync.pending > 0
        ? const Text(AppStrings.uploading)
        : const SizedBox.shrink();
  });

  /// A GPS or upload error updates this message only.
  Widget _buildErrorMessage() => Obx(() {
    final error =
        controller.errorMessage.value ?? controller.sync.errorMessage.value;
    return error == null
        ? const SizedBox.shrink()
        : Text(error, style: const TextStyle(color: Colors.red));
  });

  /// Periodic GPS selection and Start/Stop determine this switch's enabled state.
  Widget _buildSimulationSwitch() => Obx(() {
    final busy = !controller.sync.isReady.value || controller.isStarting.value;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text(AppStrings.simulateLocation),
      subtitle: const Text(AppStrings.simulationHint),
      value: controller.simulateLocation.value,
      onChanged: busy || controller.isTracking.value
          ? null
          : controller.setLocationSimulation,
    );
  });

  /// The offline switch observes its own value, independently of GPS state.
  Widget _buildOfflineSwitch() => Obx(
    () => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text(AppStrings.simulateOffline),
      value: controller.sync.connection.simulateOffline.value,
      onChanged: controller.setOfflineMode,
    ),
  );

  /// Refreshes the form field when the mock failure choice changes.
  Widget _buildMockApiDropdown() => Obx(() {
    final failure = controller.uploadFailure.value;
    return DropdownButtonFormField<DemoFailure>(
      key: ValueKey(failure),
      initialValue: failure,
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
    );
  });

  /// Upload activity only controls this action's enabled state.
  Widget _buildRetryButton() => Obx(
    () => TextButton(
      onPressed: controller.sync.isSyncing.value
          ? null
          : controller.sync.retryNow,
      child: const Text(AppStrings.retry),
    ),
  );

  /// Only the data section rebuilds when the saved records change.
  Widget _buildRecentLocations() => Obx(() {
    final records = controller.sync.records;
    if (records.isEmpty) return const Text(AppStrings.empty);
    return Column(children: records.take(10).map(_buildLocationRow).toList());
  });

  /// Formats one immutable record; its stable key preserves the row's identity.
  Widget _buildLocationRow(LocationRecord row) => ListTile(
    key: ValueKey(row.id),
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
        color: row.status == UploadStatus.synced ? Colors.green : null,
      ),
    ),
    isThreeLine: true,
  );
}
