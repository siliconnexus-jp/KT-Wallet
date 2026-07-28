import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
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

/// Maps the export's SLIP-44 records onto the app's chain address set.
///
/// Base / Arbitrum / Avalanche are populated whenever the export carries them
/// ([validateAccountExport] requires them from a production signer and
/// enforces that they equal the eth address). Passing them explicitly is what
/// makes [ChainAddresses.hasExpandedEvm] true for a paired watch wallet —
/// without it the app treated every paired wallet as a legacy four-chain
/// fixture and kept demo affordances alive on live screens. Legacy four-record
/// fixtures still omit them and keep the eth fallback.
///
/// Missing coins fall back to empty strings (the payload validator guarantees
/// 1..8 accounts but not which coins).
ChainAddresses addressesFromExport(AccountExport export) {
  String? maybeAddr(int coin) => export.accounts
      .where((a) => a.coin == coin)
      .map((a) => a.address)
      .firstOrNull;
  String addr(int coin) => maybeAddr(coin) ?? '';
  return ChainAddresses(
    eth: addr(60),
    polygon: addr(966),
    base: maybeAddr(8453),
    arbitrum: maybeAddr(42161),
    avalanche: maybeAddr(9000),
    bnb: maybeAddr(714),
    tron: addr(195),
    solana: addr(501),
  );
}

/// Validates the semantic account set after AIRGAP-V1 schema decoding. The
/// production camera requires all seven supported chain records; tests and
/// legacy demo fixtures may opt into the original four-record set.
void validateAccountExport(
  AccountExport export, {
  bool requireAllChains = true,
}) {
  final expectedPaths = <int, String>{
    60: "m/44'/60'/0'/0/0",
    966: "m/44'/60'/0'/0/0",
    8453: "m/44'/60'/0'/0/0",
    42161: "m/44'/60'/0'/0/0",
    9000: "m/44'/60'/0'/0/0",
    714: "m/44'/60'/0'/0/0",
    195: "m/44'/195'/0'/0/0",
    501: "m/44'/501'/0'",
  };
  final records = <int, AccountRecord>{};
  for (final account in export.accounts) {
    if (!expectedPaths.containsKey(account.coin) ||
        records.containsKey(account.coin) ||
        account.index != 0 ||
        account.path != expectedPaths[account.coin]) {
      throw PayloadError('invalid or duplicate account record');
    }
    final chain = switch (account.coin) {
      60 => Chain.ethereum,
      966 => Chain.polygon,
      8453 => Chain.base,
      42161 => Chain.arbitrum,
      9000 => Chain.avalanche,
      714 => Chain.bnb,
      195 => Chain.tron,
      501 => Chain.solana,
      _ => throw PayloadError('unsupported account coin'),
    };
    if (!Addresses.validate(chain, account.address).isValid) {
      throw PayloadError('invalid ${chain.name} account address');
    }
    final publicKey = account.publicKey;
    if (requireAllChains && publicKey == null) {
      throw PayloadError('account public key is required');
    }
    if (publicKey != null &&
        !_publicKeyMatchesAddress(chain, publicKey, account.address)) {
      throw PayloadError('account public key does not match address');
    }
    records[account.coin] = account;
  }
  final required = requireAllChains
      ? expectedPaths.keys.toSet()
      : const {60, 966, 195, 501};
  if (!records.keys.toSet().containsAll(required)) {
    throw PayloadError('account export is missing supported chains');
  }
  final evm = records[60]?.address.toLowerCase();
  for (final coin in const [966, 8453, 42161, 9000, 714]) {
    final value = records[coin]?.address;
    if (value != null && value.toLowerCase() != evm) {
      throw PayloadError('EVM account records do not share one key');
    }
  }
}

bool _publicKeyMatchesAddress(
  Chain chain,
  Uint8List publicKey,
  String address,
) {
  if (chain == Chain.solana) {
    return publicKey.length == 32 && base58Encode(publicKey) == address;
  }
  if (publicKey.length != 65 || publicKey.first != 4) return false;
  final body = keccak256(Uint8List.sublistView(publicKey, 1)).sublist(12);
  if (chain == Chain.tron) {
    final payload = Uint8List.fromList([0x41, ...body]);
    final checksum = sha256(sha256(payload)).sublist(0, 4);
    return base58Encode(Uint8List.fromList([...payload, ...checksum])) ==
        address;
  }
  final hex = body.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '0x$hex'.toLowerCase() == address.toLowerCase();
}
