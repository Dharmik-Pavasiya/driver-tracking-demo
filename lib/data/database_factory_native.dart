import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openOutboxDatabase() async {
  final DatabaseFactory factory;
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  } else {
    factory = mobile.databaseFactory;
  }
  return factory.openDatabase(
    path.join(await factory.getDatabasesPath(), 'driver_outbox.db'),
  );
}
