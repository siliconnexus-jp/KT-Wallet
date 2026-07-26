import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';

import '../market/balance_service.dart' show RpcEndpointResolver;
import '../market/gateway_client.dart';
import '../wallets/wallet_model.dart';
import 'airgap_codec.dart';
import 'broadcast_service.dart';
import 'chain_params_service.dart';
import 'transfer_draft.dart';

class LocalTransferException implements Exception {
  const LocalTransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Real hot-wallet path shared by the production auth sheet and integration
/// tests: fetch live EVM state, build the active network's unsigned envelope,
/// sign inside native Wallet Core, then broadcast exactly once.
class LocalTransferService {
  LocalTransferService({
    ChainParamsService? params,
    BroadcastService? broadcaster,
    RpcEndpointResolver? endpoints,
    GatewayResolver? gateway,
  }) : _params =
           params ?? ChainParamsService(endpoints: endpoints, gateway: gateway),
       _broadcaster =
           broadcaster ??
           BroadcastService(endpoints: endpoints, gateway: gateway);

  final ChainParamsService _params;
  final BroadcastService _broadcaster;

  Future<String> execute({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required TransferDraft draft,
    required int evmChainId,
  }) async {
    if (draft.chain != Chain.ethereum &&
        draft.chain != Chain.polygon &&
        draft.chain != Chain.base &&
        draft.chain != Chain.arbitrum &&
        draft.chain != Chain.avalanche) {
      throw const LocalTransferException(
        'Local signing is currently available for EVM transfers only',
      );
    }
    final from = addressForChain(wallet.addresses, draft.chain);
    final params = await _params.fetchEvmParams(draft.chain, from);
    final fees = params.tierFor(draft.feeTier);
    final unsigned = rawTxFor(
      draft,
      from: from,
      nonce: BigInt.from(params.nonce),
      maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
      maxFeePerGas: fees.maxFeePerGas,
      evmChainId: evmChainId,
    );
    final signed = await wallet.sign(
      crypto,
      coin: rpcCoinForChain(draft.chain),
      signingInput: unsigned,
    );
    final outcome = await _broadcaster.broadcast(draft.chain, signed.signedTx);
    if (outcome.status != BroadcastStatus.ok || outcome.txHash == null) {
      throw LocalTransferException(
        outcome.message ?? 'The network rejected the transaction',
      );
    }
    return outcome.txHash!;
  }
}
