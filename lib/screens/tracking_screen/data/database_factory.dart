import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Opens the same private SQLite file on every Android/iOS launch.
/// Reusing this path preserves pending points and retry deadlines after restart.
Future<Database> openOutboxDatabase() async =>
    openDatabase(path.join(await getDatabasesPath(), 'driver_outbox.db'));
