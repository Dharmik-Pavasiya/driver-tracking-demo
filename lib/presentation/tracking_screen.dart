import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/location_record.dart';
import '../services/location_api.dart';
import 'tracking_controller.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key, required this.controller});
  final TrackingController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final latest = controller.records.isEmpty
          ? null
          : controller.records.first;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Driver tracking'),
          backgroundColor: Colors.white,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Chip(
                avatar: Icon(
                  controller.network.online ? Icons.wifi : Icons.wifi_off,
                  size: 18,
                ),
                label: Text(controller.network.online ? 'Online' : 'Offline'),
              ),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Every point, accounted for.',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Simulated GPS • SQLite outbox • Idempotent REST uploads',
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.my_location,
                              color: controller.tracking
                                  ? const Color(0xFF146B52)
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                controller.tracking
                                    ? 'Tracking active'
                                    : 'Tracking stopped',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: !controller.ready
                                  ? null
                                  : () {
                                      if (controller.tracking) {
                                        unawaited(controller.stopTracking());
                                      } else {
                                        controller.startTracking();
                                      }
                                    },
                              icon: Icon(
                                controller.tracking
                                    ? Icons.stop
                                    : Icons.play_arrow,
                              ),
                              label: Text(
                                controller.tracking
                                    ? 'Stop tracking'
                                    : 'Start tracking',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 150,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _RoutePainter(controller.records),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          latest == null
                              ? 'Start tracking to capture a point every 3 seconds.'
                              : 'Latest: ${latest.latitude.toStringAsFixed(6)}, ${latest.longitude.toStringAsFixed(6)}',
                        ),
                        const Text(
                          'Illustrative route preview • simulated Bengaluru coordinates',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Metric(
                      label: 'Pending',
                      value: controller.pending,
                      color: const Color(0xFFAF6E08),
                    ),
                    const SizedBox(width: 10),
                    _Metric(
                      label: 'Synced',
                      value: controller.synced,
                      color: const Color(0xFF146B52),
                    ),
                    const SizedBox(width: 10),
                    _Metric(
                      label: 'Blocked',
                      value: controller.blocked,
                      color: Colors.redAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Demo controls',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Simulate offline'),
                          subtitle: const Text(
                            'Keep capturing locally; reconnect to synchronize automatically.',
                          ),
                          value: controller.network.simulateOffline,
                          onChanged: controller.network.setSimulateOffline,
                        ),
                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DropdownButton<DemoFailure>(
                              value: controller.api.failure,
                              onChanged: (value) {
                                if (value != null) controller.setFailure(value);
                              },
                              items: const [
                                DropdownMenuItem(
                                  value: DemoFailure.none,
                                  child: Text('API: healthy'),
                                ),
                                DropdownMenuItem(
                                  value: DemoFailure.beforeCommit,
                                  child: Text('API: fail before save (503)'),
                                ),
                                DropdownMenuItem(
                                  value: DemoFailure.afterCommit,
                                  child: Text('API: fail after save (503)'),
                                ),
                              ],
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  controller.ready &&
                                      controller.network.online &&
                                      !controller.sync.syncing
                                  ? () => unawaited(controller.retryNow())
                                  : null,
                              icon: const Icon(Icons.sync),
                              label: const Text('Retry now'),
                            ),
                            Text(
                              controller.sync.syncing ? 'Uploading…' : 'Automatic retry: 2s → 4s → 8s → 60s + jitter',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          'Mock API: ${controller.api.baseUrl}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                if (controller.storageError ?? controller.sync.lastError
                    case final String error) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0DF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(error),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Location outbox',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      '${controller.records.length} records',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (controller.records.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Your captured locations will appear here.'),
                    ),
                  ),
                ...controller.records
                    .take(30)
                    .map((record) => _RecordTile(record)),
                if (controller.records.length > 30)
                  const Text(
                    'Showing the latest 30 records. All records remain in SQLite.',
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Foreground demonstration. Native background tracking requirements are documented in the README.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

class _RecordTile extends StatelessWidget {
  const _RecordTile(this.record);
  final LocationRecord record;
  @override
  Widget build(BuildContext context) {
    final color = switch (record.status) {
      UploadStatus.pending => const Color(0xFFAF6E08),
      UploadStatus.synced => const Color(0xFF146B52),
      UploadStatus.blocked => Colors.redAccent,
    };
    final time = record.capturedAt
        .toLocal()
        .toIso8601String()
        .split('T')
        .last
        .split('.')
        .first;
    return Card(
      child: ListTile(
        leading: Icon(
          record.status == UploadStatus.synced
              ? Icons.check_circle_outline
              : Icons.schedule,
          color: color,
        ),
        title: Text(
          '${record.latitude.toStringAsFixed(6)}, ${record.longitude.toStringAsFixed(6)}',
        ),
        subtitle: Text(
          '$time • ${record.id.substring(0, min(8, record.id.length))} • ${record.attempts} attempts${record.lastError == null ? '' : '\n${record.lastError}'}',
        ),
        trailing: Text(record.status.name, style: TextStyle(color: color)),
        isThreeLine: record.lastError != null,
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.records);
  final List<LocationRecord> records;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      Paint()..color = const Color(0xFFF0F5F2),
    );
    final grid = Paint()
      ..color = const Color(0xFFDDE8E1)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 35) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 35) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    Offset point(LocationRecord r) => Offset(
      size.width * (0.5 + (r.longitude - 77.5946) / 0.008),
      size.height * (0.5 - (r.latitude - 12.9716) / 0.006),
    );
    final route = Path();
    final visible = records.take(36).toList().reversed.toList();
    for (var i = 0; i < visible.length; i++) {
      final p = point(visible[i]);
      if (i == 0) {
        route.moveTo(p.dx, p.dy);
      } else {
        route.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFF146B52)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    if (records.isNotEmpty) {
      canvas.drawCircle(
        point(records.first),
        7,
        Paint()..color = const Color(0xFF146B52),
      );
      canvas.drawCircle(point(records.first), 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.records != records;
}
