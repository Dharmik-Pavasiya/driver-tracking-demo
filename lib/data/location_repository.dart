import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../models/location_record.dart';

/// The phone mock records whether an ID is new, already accepted, or conflicting.
enum MockResult { created, duplicate, conflict }

/// SQLite is the source of truth. Each mutation targets one row, so a GPS
/// insert cannot be overwritten by an upload acknowledgement.
class LocationRepository {
  /// Accepts a phone database or a temporary SQLite database supplied by tests.
  LocationRepository(this.database);
  final Database database;

  /// Creates the outbox and its pending-record index on the first launch.
  /// Existing rows are retained on subsequent launches.
  Future<void> initialize() async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS locations (
        id TEXT PRIMARY KEY,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        capturedAt TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        nextAttemptAt INTEGER,
        lastError TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS pending_due
      ON locations(status, nextAttemptAt)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS mock_locations (
        id TEXT PRIMARY KEY,
        payload TEXT NOT NULL
      )
    ''');
  }

  /// Saves a fix before any HTTP request. The primary key ignores duplicate IDs.
  Future<void> enqueue(LocationRecord record) async {
    await database.insert(
      'locations',
      record.toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Reads records newest first for the controller's list and counters.
  Future<List<LocationRecord>> all() async => (await database.query(
    'locations',
    orderBy: 'capturedAt DESC, id',
  )).map(LocationRecord.fromRow).toList();

  /// Returns the oldest pending row whose retry deadline has passed.
  /// Returning null tells the sync worker that there is nothing ready to upload.
  Future<LocationRecord?> nextDue(DateTime now) async {
    final rows = await database.query(
      'locations',
      where: "status = 'pending' AND (nextAttemptAt IS NULL OR nextAttemptAt <= ?)",
      whereArgs: [now.millisecondsSinceEpoch],
      orderBy: 'capturedAt ASC, id',
      limit: 1,
    );
    return rows.isEmpty ? null : LocationRecord.fromRow(rows.single);
  }

  /// Counts an attempt before HTTP so an interrupted request remains visible.
  Future<void> recordAttempt(String id) async {
    await database.rawUpdate(
      'UPDATE locations SET attempts = attempts + 1 WHERE id = ?',
      [id],
    );
  }

  /// Marks only the acknowledged row synced and clears its previous failure.
  Future<void> acknowledge(String id) async {
    await database.update(
      'locations',
      {'status': 'synced', 'lastError': null, 'nextAttemptAt': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Saves an error and retry deadline, or blocks a permanent rejection.
  /// An already synced row cannot be changed back to pending by a late failure.
  Future<void> fail(
    String id, {
    required String error,
    required DateTime retryAt,
    required bool retryable,
  }) async {
    await database.update(
      'locations',
      {
        'status': retryable ? 'pending' : 'blocked',
        'lastError': error,
        'nextAttemptAt': retryAt.millisecondsSinceEpoch,
      },
      where: 'id = ? AND status != ?',
      whereArgs: [id, 'synced'],
    );
  }

  /// Explicit operator action bypasses backoff, but never resubmits synced rows.
  Future<void> retryNow() async {
    await database.update(
      'locations',
      {'status': 'pending', 'nextAttemptAt': null},
      where: 'status != ?',
      whereArgs: ['synced'],
    );
  }

  /// Saves mock-server acceptance separately from the app's pending outbox.
  /// A transaction keeps concurrent retries from accepting the same ID twice.
  Future<MockResult> acceptMock(LocationRecord record) => database.transaction((
    txn,
  ) async {
    final payload = jsonEncode(record.toPayload());
    final existing = await txn.query(
      'mock_locations',
      where: 'id = ?',
      whereArgs: [record.id],
    );
    if (existing.isNotEmpty) {
      return existing.first['payload'] == payload
          ? MockResult.duplicate
          : MockResult.conflict;
    }
    await txn.insert('mock_locations', {'id': record.id, 'payload': payload});
    return MockResult.created;
  });

  /// Lets the mock apply simulated failures only to new IDs, never to replays.
  Future<bool> mockContains(String id) async => (await database.query(
    'mock_locations',
    columns: ['id'],
    where: 'id = ?',
    whereArgs: [id],
  )).isNotEmpty;

  /// Supplies the mock's GET endpoint and duplicate-verification tests.
  Future<List<Map<String, dynamic>>> mockRecords() async =>
      (await database.query('mock_locations'))
          .map(
            (row) =>
                jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          )
          .toList();
}
