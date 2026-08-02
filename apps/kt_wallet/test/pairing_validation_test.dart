import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/wallets/pairing_airgap.dart';

Uint8List _hex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

final _secpPublicKey = _hex(
  '0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'
  '483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8',
);
final _solanaPublicKey = Uint8List.fromList(List<int>.filled(32, 7));

String _evmAddress() {
  return _evmAddressFor(_secpPublicKey);
}

String _evmAddressFor(Uint8List publicKey) {
  final body = keccak256(Uint8List.sublistView(publicKey, 1)).sublist(12);
  return '0x${body.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

String _tronAddress() {
  final body = keccak256(Uint8List.sublistView(_secpPublicKey, 1)).sublist(12);
  final payload = Uint8List.fromList([0x41, ...body]);
  final checksum = sha256(sha256(payload)).sublist(0, 4);
  return base58Encode(Uint8List.fromList([...payload, ...checksum]));
}

AccountExport _completeExport({
  Uint8List? evmPublicKey,
  String? evmAddress,
  String? solanaAddress,
  bool omitBnb = false,
}) {
  final evm = evmAddress ?? _evmAddress();
  final evmKey = evmPublicKey ?? _secpPublicKey;
  AccountRecord evmRecord(int coin) => AccountRecord(
    coin: coin,
    address: evm,
    path: evmDefaultDerivationPath,
    index: 0,
    publicKey: Uint8List.fromList(evmKey),
  );

  return AccountExport(
    walletId: 'pairing-validation-wallet',
    walletName: 'Offline wallet',
    accounts: [
      for (final coin in const [60, 966, 8453, 42161, 9000, 714])
        if (!(omitBnb && coin == 714)) evmRecord(coin),
      AccountRecord(
        coin: 195,
        address: _tronAddress(),
        path: tronDefaultDerivationPath,
        index: 0,
        publicKey: Uint8List.fromList(_secpPublicKey),
      ),
      AccountRecord(
        coin: 501,
        address: solanaAddress ?? base58Encode(_solanaPublicKey),
        path: solanaDefaultDerivationPath,
        index: 0,
        publicKey: Uint8List.fromList(_solanaPublicKey),
      ),
    ],
  );
}

void main() {
  test('complete eight-chain export binds every address to its public key', () {
    expect(
      () => validateScannedAccountExport(_completeExport()),
      returnsNormally,
    );
  });

  test('production pairing validates before constructing a watch wallet', () {
    final export = _completeExport();
    final wallet = watchWalletFromAccountExport(
      export,
      id: 'watch-from-export',
      avatarColor: 0xFF0C1220,
      sortOrder: 3,
    );
    expect(wallet.coldWalletId, export.walletId);
    expect(wallet.addresses.eth.toLowerCase(), _evmAddress().toLowerCase());
    expect(wallet.addresses.solana, base58Encode(_solanaPublicKey));
    expect(wallet.canSignLocally, isFalse);
    expect(wallet.protocolVersion, airgapVersion);
  });

  test('named Solana derivation cannot masquerade as native default', () {
    final export = _completeExport();
    final accounts = [
      for (final account in export.accounts)
        if (account.coin == 501)
          AccountRecord(
            coin: account.coin,
            address: account.address,
            path: "m/44'/501'/0'/0'",
            index: account.index,
            publicKey: account.publicKey,
          )
        else
          account,
    ];
    expect(
      () => validateScannedAccountExport(
        AccountExport(
          walletId: export.walletId,
          walletName: export.walletName,
          accounts: accounts,
        ),
      ),
      throwsA(isA<PayloadError>()),
    );
  });

  test('real scan never accepts the four-chain debug fixture', () {
    expect(
      () => validateScannedAccountExport(demoAccountExport),
      throwsA(isA<PayloadError>()),
    );
    expect(
      () => validateScannedAccountExport(
        demoAccountExport,
        allowLegacyDemo: true,
      ),
      returnsNormally,
    );
  });

  test('tampered EVM public key is rejected', () {
    final foreign = Uint8List.fromList([4, ...List<int>.filled(64, 1)]);
    expect(
      () =>
          validateScannedAccountExport(_completeExport(evmPublicKey: foreign)),
      throwsA(
        isA<PayloadError>().having(
          (error) => error.message,
          'message',
          contains('public key does not match'),
        ),
      ),
    );
  });

  test(
    'off-curve bytes are rejected even when their hashed address matches',
    () {
      final invalidPoint = Uint8List.fromList([4, ...List<int>.filled(64, 1)]);
      expect(
        () => validateScannedAccountExport(
          _completeExport(
            evmPublicKey: invalidPoint,
            evmAddress: _evmAddressFor(invalidPoint),
          ),
        ),
        throwsA(isA<PayloadError>()),
      );
    },
  );

  test('tampered Solana address is rejected', () {
    final address = base58Encode(_solanaPublicKey);
    final replacement = address[0] == 'A' ? 'B' : 'A';
    final tampered = '$replacement${address.substring(1)}';
    expect(tampered, isNot(address));
    expect(
      () => validateScannedAccountExport(
        _completeExport(solanaAddress: tampered),
      ),
      throwsA(isA<PayloadError>()),
    );
  });

  test('missing supported chain is rejected', () {
    expect(
      () => validateScannedAccountExport(_completeExport(omitBnb: true)),
      throwsA(
        isA<PayloadError>().having(
          (error) => error.message,
          'message',
          contains('missing supported chains'),
        ),
      ),
    );
  });
}
