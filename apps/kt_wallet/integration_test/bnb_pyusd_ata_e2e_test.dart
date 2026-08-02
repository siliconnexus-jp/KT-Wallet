import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';
import 'package:kt_wallet/src/state/networks.dart' show solanaDevnet;
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _walletId = 'bnb-pyusd-ata-e2e-v1';
const _bnbRpc = 'https://bsc-testnet-dataseed.bnbchain.org';
const _busdTestnet = '0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee';
const _pancakeV1Router = '0xd99d1c33f9fc3444f8101754abc46c52416550d1';
const _wrappedTestnetBnb = '0xae13d989dac2f0debff460ac112a837c89baa7cd';
const _busdRecipient = '0x000000000000000000000000000000000000dEaD';
const _solanaDevnetRpc = 'https://api.devnet.solana.com';
const _solanaMainnetRpc = 'https://api.mainnet-beta.solana.com';
const _pyusdDevnetMint = 'CXk2AMBfi3TwaEL2468s6zP8xq9NxTXjp9gjMgzeUynM';
const _jupMainnetMint = 'JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN';

// Two valid, independent Solana owners. Each platform uses a different owner
// so both runs can prove the "ATA absent before, created in the transfer"
// branch instead of observing the account created by the first platform.
const _androidRecipient = '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1';
const _iosRecipient = 'LwgkEga9yD5W1MBqWgW1XJJtBuvJEa8q71hM3VkiXnK';

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'BNB Testnet native/BUSD transfer + PYUSD Token-2022 first-receive ATA',
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
      registerE2eWalletCleanup(crypto, _walletId);
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

          // The official BNB faucet no longer exposes BUSD in its current
          // token selector. Bootstrap only when needed through the surviving
          // PancakeSwap testnet pool, then exercise the wallet's ordinary
          // BEP-20 transfer path against the legacy Binance test deployment.
          // Every transaction is chain-id 97 and spends test assets only.
          var busdBefore = await bnbRpc.erc20Balance(
            _busdTestnet,
            addresses.bnb,
          );
          if (busdBefore < BigInt.from(2) * BigInt.from(10).pow(18)) {
            // ignore: avoid_print
            print('E2E_STAGE=BUSD_BOOTSTRAP_SWAP');
            final swapHash = await _swapTestnetBnbForBusd(
              rpc: bnbRpc,
              wallet: wallet,
              crypto: crypto,
              owner: addresses.bnb,
            );
            await _waitForEvmReceipt(transport, swapHash);
            busdBefore = await bnbRpc.erc20Balance(_busdTestnet, addresses.bnb);
            // ignore: avoid_print
            print('BUSD_BOOTSTRAP_TX=$swapHash');
          }
          expect(
            busdBefore,
            greaterThanOrEqualTo(BigInt.from(10).pow(18)),
            reason: 'BSC Testnet BUSD bootstrap must fund the E2E wallet',
          );

          // ignore: avoid_print
          print('E2E_STAGE=BUSD_EXECUTE');
          final busdHash = await service.execute(
            wallet: wallet,
            crypto: crypto,
            draft: TransferDraft(
              symbol: 'BUSD',
              networkLabel: 'BNB Smart Chain Testnet',
              chain: Chain.bnb,
              recipient: _busdRecipient,
              amount: Amount.parse('1', 18, symbol: 'BUSD'),
              feeTier: 1,
              tokenContract: _busdTestnet,
            ),
            evmChainId: 97,
          );
          await _waitForEvmReceipt(transport, busdHash);
          final busdAfter = await bnbRpc.erc20Balance(
            _busdTestnet,
            addresses.bnb,
          );
          expect(busdAfter, busdBefore - BigInt.from(10).pow(18));
          // ignore: avoid_print
          print('BUSD_TESTNET_TX=$busdHash');
          // ignore: avoid_print
          print('BUSD_TESTNET_CONTRACT=$_busdTestnet');
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
              recipient: recipient,
              amount: Amount.parse('1', 6, symbol: 'PYUSD'),
              feeTier: 1,
              tokenContract: _pyusdDevnetMint,
              tokenProgram: solanaToken2022Program,
            ),
            evmChainId: 0,
            expectedNetworkIdentity: solanaDevnet.networkIdentity,
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

Future<String> _swapTestnetBnbForBusd({
  required EvmRpc rpc,
  required HotWallet wallet,
  required CoreCrypto crypto,
  required String owner,
}) async {
  final value = BigInt.from(10).pow(15); // 0.001 tBNB
  final calldata = _swapExactBnbForBusdCalldata(
    owner: owner,
    minimumBusd: BigInt.from(10).pow(18),
    deadline: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 15 * 60,
  );
  final fees = (await rpc.estimateFees()).standard;
  final gasLimit = await rpc.estimateGas(
    from: owner,
    to: _pancakeV1Router,
    value: value,
    data: '0x${_hexEncode(calldata)}',
  );
  final unsigned = Eip1559Tx(
    chainId: BigInt.from(97),
    nonce: BigInt.from(await rpc.getNonce(owner)),
    maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
    maxFeePerGas: fees.maxFeePerGas,
    gasLimit: gasLimit,
    to: Eip1559Tx.addressBytes(_pancakeV1Router),
    value: value,
    data: calldata,
  ).encodeUnsigned();
  final signed = await wallet.sign(
    crypto,
    coin: Coin.bnb,
    signingInput: unsigned,
  );
  return rpc.sendRawTransaction('0x${_hexEncode(signed.signedTx)}');
}

Uint8List _swapExactBnbForBusdCalldata({
  required String owner,
  required BigInt minimumBusd,
  required int deadline,
}) {
  // swapExactETHForTokens(uint256,address[],address,uint256)
  final hex =
      '7ff36ab5'
      '${_word(minimumBusd)}'
      '${_word(BigInt.from(128))}'
      '${_addressWord(owner)}'
      '${_word(BigInt.from(deadline))}'
      '${_word(BigInt.two)}'
      '${_addressWord(_wrappedTestnetBnb)}'
      '${_addressWord(_busdTestnet)}';
  return _hexDecode(hex);
}

String _word(BigInt value) => value.toRadixString(16).padLeft(64, '0');

String _addressWord(String address) =>
    address.replaceFirst(RegExp(r'^0x'), '').toLowerCase().padLeft(64, '0');

String _hexEncode(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List _hexDecode(String hex) => Uint8List.fromList([
  for (var offset = 0; offset < hex.length; offset += 2)
    int.parse(hex.substring(offset, offset + 2), radix: 16),
]);

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
