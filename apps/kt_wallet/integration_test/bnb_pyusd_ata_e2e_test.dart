import 'dart:async';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _walletId = 'bnb-pyusd-ata-e2e-v1';
const _bnbRpc = 'https://bsc-testnet-dataseed.bnbchain.org';
const _solanaDevnetRpc = 'https://api.devnet.solana.com';
const _solanaMainnetRpc = 'https://api.mainnet-beta.solana.com';
const _pyusdDevnetMint = 'CXk2AMBfi3TwaEL2468s6zP8xq9NxTXjp9gjMgzeUynM';
const _jupMainnetMint = 'JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN';

// Two valid, independent Solana owners. Each platform uses a different owner
// so both runs can prove the "ATA absent before, created in the transfer"
// branch instead of observing the account created by the first platform.
const _androidRecipient = '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1';
const _iosRecipient = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'BNB Testnet native transfer + PYUSD Token-2022 first-receive ATA',
    (tester) async {
      const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
      const platform = String.fromEnvironment(
        'E2E_PLATFORM',
        defaultValue: 'android',
      );
      const selected = String.fromEnvironment(
        'E2E_CHAINS',
        defaultValue: 'BNB,SOLANA',
      );
      expect(mnemonic, isNotEmpty);
      expect(platform, anyOf('android', 'ios'));

      final crypto = MethodChannelCoreCrypto();
      // ignore: avoid_print
      print('E2E_STAGE=STORE_WALLET');
      await crypto.storeWallet(
        walletId: _walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      // ignore: avoid_print
      print('E2E_STAGE=DERIVE_ADDRESSES');
      final addresses = await crypto.deriveAddresses(_walletId);
      final wallet = HotWallet(
        id: _walletId,
        name: 'BNB / Solana E2E',
        avatarColor: 0xFFF3BA2F,
        addresses: addresses,
        backedUp: true,
      );
      final transport = HttpJsonRpcTransport(
        timeout: const Duration(seconds: 30),
      );
      final bnbRpc = EvmRpc(url: _bnbRpc, transport: transport);
      final solanaRpc = SolanaRpc(url: _solanaDevnetRpc, transport: transport);
      final service = LocalTransferService(
        endpoints: (coin) => switch (coin) {
          Coin.bnb => _bnbRpc,
          Coin.solana => _solanaDevnetRpc,
          _ => throw StateError('unexpected E2E coin: $coin'),
        },
        jsonRpcTransport: transport,
      );

      try {
        if (selected.split(',').contains('BNB')) {
          // ignore: avoid_print
          print('E2E_STAGE=BNB_BALANCE');
          final bnbBefore = await bnbRpc.getBalance(addresses.bnb);
          expect(
            bnbBefore,
            greaterThan(BigInt.from(100000000000000)),
            reason: 'Fund the documented public E2E account with tBNB first',
          );
          final bnbHash = await service.execute(
            wallet: wallet,
            crypto: crypto,
            draft: TransferDraft(
              symbol: 'BNB',
              networkLabel: 'BNB Smart Chain Testnet',
              chain: Chain.bnb,
              decimals: 18,
              recipient: addresses.bnb,
              amount: Amount.parse('0.00001', 18, symbol: 'BNB'),
              feeTier: 1,
            ),
            evmChainId: 97,
          );
          await _waitForEvmReceipt(transport, bnbHash);
          final bnbAfter = await bnbRpc.getBalance(addresses.bnb);
          expect(bnbAfter, lessThan(bnbBefore));
          // ignore: avoid_print
          print('BNB_TESTNET_TX=$bnbHash');
        }

        if (selected.split(',').contains('SOLANA')) {
          final recipient = platform == 'ios'
              ? _iosRecipient
              : _androidRecipient;
          // ignore: avoid_print
          print('E2E_STAGE=PYUSD_PRECONDITION');
          final destinationBefore = await solanaRpc.getTokenAccounts(
            recipient,
            _pyusdDevnetMint,
          );
          expect(
            destinationBefore,
            isEmpty,
            reason:
                '$platform recipient must exercise first-receive ATA creation',
          );
          final pyusdBefore = await solanaRpc.getTokenBalance(
            addresses.solana,
            _pyusdDevnetMint,
          );
          expect(pyusdBefore, greaterThanOrEqualTo(BigInt.from(1000000)));

          // ignore: avoid_print
          print('E2E_STAGE=PYUSD_EXECUTE');
          final pyusdHash = await service.execute(
            wallet: wallet,
            crypto: crypto,
            draft: TransferDraft(
              symbol: 'PYUSD',
              networkLabel: 'Solana Devnet',
              chain: Chain.solana,
              decimals: 6,
              recipient: recipient,
              amount: Amount.parse('1', 6, symbol: 'PYUSD'),
              feeTier: 1,
              tokenContract: _pyusdDevnetMint,
              tokenProgram: solanaToken2022Program,
            ),
            evmChainId: 0,
          );
          // ignore: avoid_print
          print('E2E_STAGE=PYUSD_CONFIRM');
          await _waitForSolanaConfirmation(solanaRpc, pyusdHash);

          final destinationAfter = await solanaRpc.getTokenAccounts(
            recipient,
            _pyusdDevnetMint,
          );
          expect(destinationAfter, hasLength(1));
          expect(destinationAfter.single.amount, BigInt.from(1000000));
          expect(
            destinationAfter.single.address,
            SolanaMessage.associatedTokenAddress(
              owner: recipient,
              mint: _pyusdDevnetMint,
              tokenProgram: solanaToken2022Program,
            ),
          );
          expect(
            await solanaRpc.getTokenBalance(addresses.solana, _pyusdDevnetMint),
            pyusdBefore - BigInt.from(1000000),
          );

          // ignore: avoid_print
          print('E2E_STAGE=JUP_IDENTITY');
          await _verifyJupiterMainnetIdentityAndAta(
            transport,
            owner: recipient,
          );

          // Public test evidence only. No mnemonic or private key is printed.
          // ignore: avoid_print
          print('PYUSD_DEVNET_TX=$pyusdHash');
          // ignore: avoid_print
          print('PYUSD_RECIPIENT_ATA=${destinationAfter.single.address}');
          // ignore: avoid_print
          print(
            'JUP_MAINNET_ATA=${SolanaMessage.associatedTokenAddress(owner: recipient, mint: _jupMainnetMint)}',
          );
        }
      } finally {
        transport.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<void> _waitForEvmReceipt(JsonRpcTransport transport, String hash) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final response = await transport.post(_bnbRpc, {
      'jsonrpc': '2.0',
      'id': attempt + 1,
      'method': 'eth_getTransactionReceipt',
      'params': [hash],
    });
    final result = response is Map ? response['result'] : null;
    if (result is Map) {
      expect(result['status'], '0x1');
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw TimeoutException('BNB receipt not mined: $hash');
}

Future<void> _waitForSolanaConfirmation(SolanaRpc rpc, String signature) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final status = await rpc.signatureStatus(signature);
    if (status == 'confirmed' || status == 'finalized') return;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw TimeoutException('Solana transaction not confirmed: $signature');
}

Future<void> _verifyJupiterMainnetIdentityAndAta(
  JsonRpcTransport transport, {
  required String owner,
}) async {
  final response = await transport.post(_solanaMainnetRpc, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'getAccountInfo',
    'params': [
      _jupMainnetMint,
      {'encoding': 'jsonParsed', 'commitment': 'confirmed'},
    ],
  });
  final result = response is Map ? response['result'] : null;
  final value = result is Map ? result['value'] : null;
  expect(value, isA<Map<Object?, Object?>>());
  expect((value as Map<Object?, Object?>)['owner'], solanaTokenProgram);
  expect(
    SolanaMessage.associatedTokenAddress(owner: owner, mint: _jupMainnetMint),
    hasLength(44),
  );
}
