import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_data/wallet_data.dart' show Contact, CustomToken;

import '../../l10n/app_localizations.dart';
import 'wallet_store.dart';

/// Seeds the demo address-book contacts and token list exactly once per
/// install — including installs upgrading from the pre-directory schema,
/// whose wallets already exist so the first-run wallet seeding never runs
/// again. Guarded by a persisted flag so a user who deletes every row does
/// not get them resurrected on the next launch; the per-table emptiness check
/// keeps us from double-seeding alongside a concurrent first run.
Future<void> seedDirectoryDefaults(WalletStore store, AppLocalizations l10n) async {
  const flagKey = 'seed.directoryDefaults.v1';
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(flagKey) ?? false) return;
  } catch (_) {
    // No prefs plugin (tests): fall through and rely on the emptiness checks.
  }

  if ((await store.listContacts()).isEmpty) {
    for (final (i, (id, name, address, chain)) in [
      ('contact-alice', 'Alice', '0x71c8B2…9F3dA24', 'ethereum'),
      ('contact-bob', l10n.contactBobExchange, 'TWd4qCEU…nMxR38uQz', 'tron'),
      ('contact-cold', l10n.contactColdBackup, '0x8f3C2a…7E19bE1', 'polygon'),
      ('contact-dana', 'Dana', '6yKp…Vr2W', 'solana'),
    ].indexed) {
      await store.addContact(Contact(id: id, name: name, address: address, chain: chain, createdAt: i));
    }
  }

  if ((await store.listTokens()).isEmpty) {
    for (final (i, (id, symbol, name, network, enabled)) in [
      ('token-usdt-tron', 'USDT', 'Tether USD', 'TRON · TRC-20', true),
      ('token-usdt-eth', 'USDT', 'Tether USD', 'Ethereum · ERC-20', true),
      ('token-usdc-sol', 'USDC', 'USD Coin', 'Solana · SPL', true),
      ('token-busd-eth', 'BUSD', 'Binance USD', 'Ethereum · ERC-20', false),
      ('token-uni-eth', 'UNI', 'Uniswap', 'Ethereum · ERC-20', false),
    ].indexed) {
      await store.addToken(CustomToken(
        id: id,
        symbol: symbol,
        name: name,
        contract: null,
        network: network,
        enabled: enabled,
        sortOrder: i,
        createdAt: i,
      ));
    }
  }

  try {
    await prefs?.setBool(flagKey, true);
  } catch (_) {
    // Best-effort; worst case the emptiness checks re-run next launch.
  }
}
