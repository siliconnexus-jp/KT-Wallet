// Live P7 smoke test: exercises the chains RPC clients against public testnet
// nodes to prove the parsing/transport works end-to-end (detailed-design.md
// §4.3, todolist.md P7-1). Requires network; run manually:
//
//   dart run apps/kt_wallet/tool/testnet_smoke.dart
//
// It performs READ-ONLY queries only (balances / blockhash) — no broadcasting.
//
// ignore_for_file: avoid_print

import 'package:chains/rpc.dart';
import 'package:kt_wallet/src/rpc/http_transport.dart';

// Public testnet endpoints (read-only, no key required).
const _sepoliaRpc = 'https://ethereum-sepolia-rpc.publicnode.com';
const _amoyRpc = 'https://polygon-amoy-bor-rpc.publicnode.com';
const _solanaDevnet = 'https://api.devnet.solana.com';
const _tronNile = 'https://nile.trongrid.io';

// A well-known address that exists on each network (read-only lookups).
const _evmAddr = '0x0000000000000000000000000000000000000000';
const _solAddr = 'So11111111111111111111111111111111111111112';
const _tronAddr = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

Future<void> _run(String label, Future<void> Function() body) async {
  try {
    await body();
    print('  PASS  $label');
  } catch (e) {
    print('  FAIL  $label -> $e');
  }
}

Future<void> main() async {
  final jsonRpc = HttpJsonRpcTransport();
  final rest = HttpRestTransport();

  print('EVM (Sepolia)');
  final sepolia = EvmRpc(url: _sepoliaRpc, transport: jsonRpc);
  await _run('getBalance(zero address)', () async {
    final bal = await sepolia.getBalance(_evmAddr);
    print('        balance=$bal wei');
  });
  await _run('feeHistory 3-tier estimate', () async {
    final fees = await sepolia.estimateFees();
    print(
      '        slow/std/fast maxFee = '
      '${fees.slow.maxFeePerGas}/${fees.standard.maxFeePerGas}/${fees.fast.maxFeePerGas}',
    );
  });

  print('EVM (Polygon Amoy)');
  final amoy = EvmRpc(url: _amoyRpc, transport: jsonRpc);
  await _run('getNonce(zero address)', () async {
    print('        nonce=${await amoy.getNonce(_evmAddr)}');
  });

  print('Solana (Devnet)');
  final sol = SolanaRpc(url: _solanaDevnet, transport: jsonRpc);
  await _run('getBalance', () async {
    print('        lamports=${await sol.getBalance(_solAddr)}');
  });
  await _run('getLatestBlockhash', () async {
    print('        blockhash=${await sol.getLatestBlockhash()}');
  });

  print('TRON (Nile)');
  final tron = TronRpc(baseUrl: _tronNile, transport: rest);
  await _run('getTrxBalance', () async {
    print('        sun=${await tron.getTrxBalance(_tronAddr)}');
  });
  await _run('getNowBlock (refBlock)', () async {
    final block = await tron.getNowBlock();
    print('        block=${block.number}');
  });

  jsonRpc.close();
  rest.close();
}
