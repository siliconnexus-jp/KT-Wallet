import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'signer_database.dart';

/// Opens the on-device SQLite database for the Cold Signer (anti-replay
/// sign_records). Used by the production entrypoint; tests inject
/// `SignerDatabase(NativeDatabase.memory())` instead. Same lazy-open pattern
/// as kt_wallet's database_provider.dart.
SignerDatabase openSignerDatabase() => SignerDatabase(_lazyNativeConnection());

LazyDatabase _lazyNativeConnection() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'cold_signer.sqlite'));
  return NativeDatabase.createInBackground(file);
});
