import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wallet_data/wallet_data.dart';

/// Opens the on-device SQLite database for the wallet app. Used by the
/// production entrypoint; tests inject an in-memory controller instead.
WalletDatabase openWalletDatabase() => WalletDatabase(_lazyNativeConnection());

LazyDatabase _lazyNativeConnection() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'kt_wallet.sqlite'));
  return NativeDatabase.createInBackground(file);
});
