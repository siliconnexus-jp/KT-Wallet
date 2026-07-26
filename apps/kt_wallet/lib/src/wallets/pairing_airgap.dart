import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:core_crypto/core_crypto.dart';

/// Canonical demo pairing session: the AccountExport payload the offline
/// signer's C10 export screen emits for the demo watch wallet. The values
/// match the online app's seeded 主钱包 (WLT-3E8A91) so the paired result is
/// the same wallet the design shows. Production replaces this with the
/// signer's real derived accounts; the protocol path (fragment → optical →
/// aggregate → decode) is the real one already.
final demoAccountExport = AccountExport(
  walletId: 'WLT-3E8A91',
  walletName: '主钱包',
  accounts: [
    AccountRecord(
      coin: 60,
      address: '0xc71c8B29b3d4b79E19bE1',
      path: "m/44'/60'/0'/0/0",
      index: 0,
    ),
    AccountRecord(
      coin: 966,
      address: '0xc71c8B29b3d4b79E19bE1',
      path: "m/44'/60'/0'/0/0",
      index: 0,
    ),
    AccountRecord(
      coin: 195,
      address: 'TcPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
      path: "m/44'/195'/0'/0/0",
      index: 0,
    ),
    AccountRecord(
      coin: 501,
      address: 'cyKpXwMWd4qmDqVr2W',
      path: "m/44'/501'/0'",
      index: 0,
    ),
  ],
);

/// Fixed session id so tests are deterministic; a real signer mints one per
/// export session.
final demoPairingReqId = Uint8List.fromList([
  0xA1,
  0x7B,
  0x3E,
  0x8A,
  0x91,
  0x00,
  0x00,
  0x01,
]);

/// Small chunk size (production default is far larger) so even this compact
/// demo payload spans several frames and the aggregation UX is exercised.
const pairingChunkSize = 64;

/// The wire frames exactly as the signer's export screen emits them.
List<AirgapFrame> demoAccountExportFrames() => Fragmenter(
  chunkSize: pairingChunkSize,
).fragment(demoAccountExport.encode(), reqId: demoPairingReqId);

/// Maps the export's SLIP-44 records onto the app's fixed four-chain address
/// set. Missing coins fall back to empty strings (the payload validator
/// guarantees 1..8 accounts but not which coins; the demo always carries all
/// four).
ChainAddresses addressesFromExport(AccountExport export) {
  String addr(int coin) =>
      export.accounts
          .where((a) => a.coin == coin)
          .map((a) => a.address)
          .firstOrNull ??
      '';
  return ChainAddresses(
    eth: addr(60),
    polygon: addr(966),
    tron: addr(195),
    solana: addr(501),
  );
}
