/// Pending rows can upload; synced rows are finished; blocked rows need review.
enum UploadStatus { pending, synced, blocked }

/// The identity and payload never change between attempts.
class LocationRecord {
  /// Creates a location and its local upload metadata.
  const LocationRecord({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.status = UploadStatus.pending,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
  });

  final String id;
  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final UploadStatus status;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;

  /// Builds the immutable JSON body used for every upload attempt.
  /// Local status and retry fields are deliberately not sent to the server.
  Map<String, Object?> toPayload() => {
    'id': id,
    'latitude': latitude,
    'longitude': longitude,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };

  /// Includes retry metadata when writing this record into SQLite.
  Map<String, Object?> toRow() => {
    ...toPayload(),
    'status': status.name,
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt?.millisecondsSinceEpoch,
    'lastError': lastError,
  };

  /// Restores a saved row, including its next retry time after an app restart.
  factory LocationRecord.fromRow(Map<String, Object?> row) => LocationRecord(
    id: row['id'] as String,
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
    capturedAt: DateTime.parse(row['capturedAt'] as String),
    status: UploadStatus.values.byName(row['status'] as String),
    attempts: row['attempts'] as int,
    nextAttemptAt: row['nextAttemptAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            row['nextAttemptAt'] as int,
            isUtc: true,
          ),
    lastError: row['lastError'] as String?,
  );
}
