import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/wallets/directory_seeder.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_data/wallet_data.dart';

/// Regression for the v1→v2 upgrade hole: wallets already exist, so first-run
/// seeding never fires again — the directory seeder must still populate the
/// new contacts/tokens tables exactly once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WalletDatabase db;
  late WalletStore store;
  late AppLocalizations l10n;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = WalletDatabase(NativeDatabase.memory());
    store = WalletStore(db);
    l10n = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  tearDown(() => db.close());

  test('upgraded install (wallets exist, empty directory tables) gets seeded', () async {
    // No wallet rows needed — the seeder never looks at them; what matters is
    // that it runs independently of first-run wallet seeding.
    await seedDirectoryDefaults(store, l10n);

    expect((await store.listContacts()).length, 4);
    expect((await store.listTokens()).length, 5);
  });

  test('seeding is idempotent and does not duplicate rows', () async {
    await seedDirectoryDefaults(store, l10n);
    await seedDirectoryDefaults(store, l10n);

    expect((await store.listContacts()).length, 4);
    expect((await store.listTokens()).length, 5);
  });

  test('rows deleted by the user are not resurrected once the flag is set', () async {
    await seedDirectoryDefaults(store, l10n);
    for (final c in await store.listContacts()) {
      await store.deleteContact(c.id);
    }
    expect(await store.listContacts(), isEmpty);

    await seedDirectoryDefaults(store, l10n);
    expect(await store.listContacts(), isEmpty, reason: 'flag must prevent re-seeding');
  });
}
