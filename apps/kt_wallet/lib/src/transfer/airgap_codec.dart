import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses;

import 'transfer_draft.dart';

/// Pure helpers that turn a [TransferDraft] into real AIRGAP-V1 protocol
/// bytes (and back). All logic here is deterministic and framework-free so
/// the round-trip is unit-testable; the screens only render what these
/// functions produce.

// ---- chain <-> protocol mappings -------------------------------------------

/// SLIP-44 coin types (same convention as the airgap_protocol fixtures and
/// the wallet-core derivation paths).
int coinForChain(Chain chain) => switch (chain) {
  Chain.ethereum => 60,
  Chain.polygon => 966,
  Chain.base => 8453,
  Chain.arbitrum => 42161,
  Chain.avalanche => 9000,
  Chain.bnb => 714,
  Chain.tron => 195,
  Chain.solana => 501,
};

Chain chainForCoin(int coin) => switch (coin) {
  60 => Chain.ethereum,
  966 => Chain.polygon,
  8453 => Chain.base,
  42161 => Chain.arbitrum,
  9000 => Chain.avalanche,
  714 => Chain.bnb,
  195 => Chain.tron,
  501 => Chain.solana,
  _ => throw ArgumentError('unsupported coin type $coin'),
};

/// DEFAULT (mainnet) EVM chain id where applicable; null for non-EVM chains.
/// The live transfer flow passes the ACTIVE network's evmChainId instead
/// (Sepolia 11155111, Amoy 80002, ...) — these constants only back demo /
/// golden renderings and callers without a network source.
int? chainIdForChain(Chain chain) => switch (chain) {
  Chain.ethereum => 1,
  Chain.polygon => 137,
  Chain.base => 8453,
  Chain.arbitrum => 42161,
  Chain.avalanche => 43114,
  Chain.bnb => 56,
  _ => null,
};

String addressForChain(ChainAddresses addresses, Chain chain) =>
    switch (chain) {
      Chain.ethereum => addresses.eth,
      Chain.polygon => addresses.polygon,
      Chain.base => addresses.base,
      Chain.arbitrum => addresses.arbitrum,
      Chain.avalanche => addresses.avalanche,
      Chain.bnb => addresses.bnb,
      Chain.tron => addresses.tron,
      Chain.solana => addresses.solana,
    };

// ---- demo fee schedule ------------------------------------------------------

/// DEMO fee schedule per chain: (slow, standard, fast) in the native unit.
///
/// DO NOT SHOW THIS TO A USER WHO IS ABOUT TO SIGN. These are invented static
/// tiers; the fee a live transaction actually pays comes from
/// [ChainParamsService] (`gasLimit * maxFeePerGas` of the selected tier) and
/// is what [Eip1559Tx] carries. This schedule may only back renderings with
/// NO live draft — the design gallery and the goldens — and the placeholder
/// raw-tx encoding for chains whose real serialization is not wired yet.
Amount networkFeeFor(Chain chain, int feeTier) {
  final (tiers, decimals, symbol) = switch (chain) {
    Chain.tron => (('6.8', '13.7', '27.4'), 6, 'TRX'),
    Chain.ethereum => (('0.00021', '0.00042', '0.00084'), 18, 'ETH'),
    Chain.polygon => (('0.01', '0.02', '0.04'), 18, 'POL'),
    Chain.base => (('0.000001', '0.000002', '0.000004'), 18, 'ETH'),
    Chain.arbitrum => (('0.00001', '0.00002', '0.00004'), 18, 'ETH'),
    Chain.avalanche => (('0.0005', '0.001', '0.002'), 18, 'AVAX'),
    Chain.bnb => (('0.0001', '0.0002', '0.0004'), 18, 'BNB'),
    Chain.solana => (('0.000005', '0.00001', '0.00002'), 9, 'SOL'),
  };
  final value = switch (feeTier) {
    0 => tiers.$1,
    2 => tiers.$3,
    _ => tiers.$2,
  };
  return Amount.parse(value, decimals, symbol: symbol);
}

/// Builds a [TxPreview] from the draft via the chains types.
///
/// Its `networkFee` / `maxFee` (and therefore `totalNativeSpend`) come from
/// the DEMO [networkFeeFor] schedule and must not be displayed for a live
/// draft — the confirm screen derives those two rows from the fetched chain
/// params instead and only uses this for the chain/from/to/amount framing.
TxPreview previewForDraft(TransferDraft draft, {required String from}) {
  final fee = networkFeeFor(draft.chain, draft.feeTier);
  final intent = TransferIntent(
    chain: draft.chain,
    operation: draft.operation,
    from: from,
    to: draft.recipient,
    amount: draft.amount,
    tokenContract: draft.tokenContract,
    tokenSymbol: draft.tokenContract == null ? null : draft.symbol,
  );
  return TxPreview(
    chain: intent.chain,
    operation: intent.operation,
    from: intent.from,
    to: intent.to,
    amount: intent.amount,
    networkFee: fee,
    maxFee: fee,
    tokenContract: intent.tokenContract,
    trustedToken: true,
  );
}

// ---- demo identity (gallery / goldens) --------------------------------------

/// TRC-20 USDT contract (also the demo default in the transfer input screen).
const usdtTronContract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

/// Values matching the Pencil design demo literals, used whenever a screen is
/// rendered without a live draft (gallery index / golden tests) so those
/// renderings stay deterministic.
final TransferDraft demoDraft = TransferDraft(
  symbol: 'USDT',
  networkLabel: 'TRON · TRC-20',
  chain: Chain.tron,
  recipient: 'TWd4qCEUf3aVpXe2HKk9gJt6nMxR38uQz',
  amount: Amount.parse('120.00', 6, symbol: 'USDT'),
  feeTier: 1,
  tokenContract: usdtTronContract,
);

const demoWalletId = 'WLT-91A4C7';

/// Fixed demo reqId — its first three bytes render as the design's
/// `REQ-7F3A2C` label, and being constant keeps the demo QR golden-stable.
final Uint8List demoReqId = Uint8List.fromList(const [
  0x7F,
  0x3A,
  0x2C,
  0x91,
  0x5D,
  0x08,
  0xB4,
  0xE6,
]);

/// Fixed demo timestamp (2026-01-01T00:00:00Z) for golden determinism.
const demoCreatedAtSec = 1767225600;

// ---- sign-request construction ----------------------------------------------

Uint8List randomReqId() {
  final rng = Random.secure();
  return Uint8List.fromList(
    List.generate(AirgapLimits.reqIdLength, (_) => rng.nextInt(256)),
  );
}

/// Expiry window for a displayed sign-request (well under
/// [AirgapLimits.maxExpirySeconds]).
const signRequestTtlSeconds = 600;

/// Raw transaction bytes for the sign request.
///
/// EVM chains carry a REAL typed transaction: `0x02 || rlp(...)` unsigned
/// EIP-1559 bytes from the chains package (native transfer, ERC-20 `transfer`,
/// or exact `approve(spender, 0)` revocation calldata) — exactly what a signer
/// hashes and signs. The
/// optional [nonce] / [maxPriorityFeePerGas] / [maxFeePerGas] overrides
/// carry live chain-state parameters (ChainParamsService); when absent the
/// documented DEMO constants apply, so every demo/golden rendering stays
/// byte-identical. The optional [evmChainId] carries the ACTIVE network's
/// signing-domain id (testnets: Sepolia 11155111, Amoy 80002) — absent, the
/// mainnet [chainIdForChain] constants apply, and a wrong-network signature
/// is invalid by construction, which is exactly the isolation we want.
/// Production TRON and Solana routes must pass [preparedRawTx]: respectively
/// the canonical `Transaction.raw` protobuf and the exact legacy message from
/// their immutable quote. The JSON fallback below exists only for isolated
/// gallery/widget fixtures and is never accepted by a release Cold Signer.
Uint8List rawTxFor(
  TransferDraft draft, {
  required String from,
  BigInt? nonce,
  BigInt? maxPriorityFeePerGas,
  BigInt? maxFeePerGas,
  BigInt? gasLimit,
  int? evmChainId,
  Uint8List? preparedRawTx,
}) {
  if (draft.chain == Chain.ethereum ||
      draft.chain == Chain.polygon ||
      draft.chain == Chain.base ||
      draft.chain == Chain.arbitrum ||
      draft.chain == Chain.avalanche ||
      draft.chain == Chain.bnb) {
    final intent = TransferIntent(
      chain: draft.chain,
      operation: draft.operation,
      from: from,
      to: draft.recipient,
      amount: draft.amount,
      tokenContract: draft.tokenContract,
      tokenSymbol: draft.tokenContract == null ? null : draft.symbol,
    );
    final gwei = BigInt.from(1000000000);
    final tx = Eip1559Tx.forTransfer(
      intent,
      chainId: BigInt.from(evmChainId ?? chainIdForChain(draft.chain) ?? 1),
      // Live overrides when provided; demo constants otherwise (see above).
      nonce: nonce ?? BigInt.zero,
      maxPriorityFeePerGas: maxPriorityFeePerGas ?? BigInt.two * gwei,
      maxFeePerGas: maxFeePerGas ?? BigInt.from(40) * gwei,
      // Arbitrum accounts for L1 posting overhead in its gas estimate, so a
      // plain 21,000 limit is rejected as "intrinsic gas too low".
      gasLimit:
          gasLimit ??
          BigInt.from(
            draft.operation == TxOperation.nativeTransfer
                ? (draft.chain == Chain.arbitrum ? 100000 : 21000)
                : (draft.chain == Chain.arbitrum ? 150000 : 65000),
          ),
    );
    return tx.encodeUnsigned();
  }
  if (preparedRawTx != null) {
    return Uint8List.fromList(preparedRawTx);
  }
  return _jsonRawTx(draft, from: from);
}

/// Deterministic JSON fixture for gallery/widget tests that do not construct a
/// live TRON/Solana quote. Release signing rejects this shape structurally.
Uint8List _jsonRawTx(TransferDraft draft, {required String from}) =>
    Uint8List.fromList(
      utf8.encode(
        json.encode({
          'v': 1,
          'chain': draft.chain.name,
          'operation': draft.operation.name,
          'from': from,
          'to': draft.recipient,
          'amountRaw': draft.amount.raw.toString(),
          'decimals': draft.decimals,
          'symbol': draft.symbol,
          if (draft.tokenContract != null) 'contract': draft.tokenContract,
          'fee': networkFeeFor(draft.chain, draft.feeTier).toString(),
        }),
      ),
    );

/// Back-compat alias for existing tests/callers; the demo (TRON) draft keeps
/// its JSON placeholder shape under either name.
Uint8List demoRawTx(TransferDraft draft, {required String from}) =>
    rawTxFor(draft, from: from);

/// Integer keys of the sign-request `summary` display-hint map.
abstract final class SummaryKeys {
  static const network = 0;
  static const amount = 1;
  static const recipient = 2;
}

/// Builds the real [SignRequest] for W6. With a live [draft], the reqId is
/// random (Random.secure) and timestamps are now-based; without one (gallery /
/// goldens) the fixed demo identity keeps the rendering deterministic. The
/// optional EVM chain-state overrides pass straight through to [rawTxFor];
/// [evmChainId] is the ACTIVE network's signing-domain id (also lands in the
/// protocol's chainId field), defaulting to the mainnet constants; and
/// [networkLabel] overrides the summary's network line so a testnet request
/// tells the signer the truth (e.g. 'Sepolia' instead of 'Ethereum').
SignRequest buildSignRequest({
  TransferDraft? draft,
  required String walletId,
  required String fromAddress,
  Uint8List? reqId,
  int? nowEpochSeconds,
  BigInt? nonce,
  BigInt? maxPriorityFeePerGas,
  BigInt? maxFeePerGas,
  BigInt? gasLimit,
  int? evmChainId,
  String? networkLabel,
  Uint8List? preparedRawTx,
}) {
  final live = draft != null;
  final d = draft ?? demoDraft;
  final created =
      nowEpochSeconds ??
      (live ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : demoCreatedAtSec);
  return SignRequest(
    reqId: reqId ?? (live ? randomReqId() : demoReqId),
    // A wallet identity is an authority boundary shared with the offline
    // signer. Never truncate or normalize it into a different identity.
    walletId: walletId,
    coin: coinForChain(d.chain),
    // Non-EVM chains have no signing-domain id; EVM chains carry the active
    // network's (defaulting to mainnet).
    chainId: chainIdForChain(d.chain) == null
        ? null
        : (evmChainId ?? chainIdForChain(d.chain)),
    rawTx: rawTxFor(
      d,
      from: fromAddress,
      nonce: nonce,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      maxFeePerGas: maxFeePerGas,
      gasLimit: gasLimit,
      evmChainId: evmChainId,
      preparedRawTx: preparedRawTx,
    ),
    summary: {
      SummaryKeys.network: networkLabel ?? d.networkLabel,
      SummaryKeys.amount: d.operation == TxOperation.approvalRevoke
          ? 'approve(spender, 0)'
          : d.amountText,
      SummaryKeys.recipient: d.recipient,
    },
    createdAt: created,
    expiresAt: created + signRequestTtlSeconds,
  );
}

// ---- frame encode / decode ---------------------------------------------------

/// Chunk size for the animated QR. Tuned below the protocol default (400) so
/// even the small demo payload spans several frames and the frame-cycling
/// loop is exercised for real, while each frame stays comfortably scannable.
const airgapChunkSize = 120;

/// Fragments a payload and encodes each frame as the base64url string that a
/// single QR in the animation carries.
List<String> encodeQrFrames(
  AirgapPayload payload, {
  required Uint8List reqId,
}) => [
  for (final frame in Fragmenter(
    chunkSize: airgapChunkSize,
  ).fragment(payload.encode(), reqId: reqId))
    base64Url.encode(frame.encode()),
];

// ---- sign-result (simulated signer) -------------------------------------------

/// What the Cold Signer would answer for [request]. The signature bytes and
/// tx hash are deterministic demo values derived from the request (the camera
/// — and the signer's key — stay simulated); everything around them is the
/// genuine AIRGAP-V1 encoding.
SignResult buildDemoSignResult(SignRequest request, {required String signer}) {
  final signedTx = Uint8List.fromList([
    ...utf8.encode('SIGNED-V1:'),
    ...request.rawTx,
  ]);
  return SignResult(
    reqId: request.reqId,
    walletId: request.walletId,
    coin: request.coin,
    signedTx: signedTx,
    signer: signer,
    txHash: hexEncode(sha256(signedTx)),
  );
}

/// Wallet-side ingestion of scanned result frames: parse each QR string,
/// aggregate (dedupe/CRC via [FrameAggregator]), decode the payload, and
/// verify it answers [expected] (reqId / walletId / coin must match — the
/// return-path counterpart of the signer's §3.4 checks).
SignResult decodeSignResultFrames(
  List<String> qrFrames, {
  required SignRequest expected,
}) {
  final aggregator = FrameAggregator();
  for (final qr in qrFrames) {
    aggregator.addFrame(AirgapFrame.decode(base64Url.decode(qr)));
    if (aggregator.state == AggregatorState.done) break;
  }
  if (aggregator.state != AggregatorState.done) {
    throw StateError(
      'incomplete frame set: ${aggregator.state}'
      '${aggregator.failure == null ? '' : ' (${aggregator.failure})'}',
    );
  }
  return verifySignResultPayload(aggregator.payload!, expected: expected);
}

/// Decodes an assembled payload as a [SignResult] and verifies it answers
/// [expected] — the shared tail of [decodeSignResultFrames], also used by the
/// live camera path where frames arrive one by one instead of as a list.
SignResult verifySignResultPayload(
  Uint8List payload, {
  required SignRequest expected,
}) {
  final decoded = AirgapPayload.decode(payload);
  if (decoded is! SignResult) {
    throw StateError('expected a sign-result payload, got ${decoded.type}');
  }
  if (decoded.reqIdHex != expected.reqIdHex) {
    throw StateError('sign-result answers a different request');
  }
  if (decoded.walletId != expected.walletId) {
    throw StateError('sign-result wallet mismatch');
  }
  if (decoded.coin != expected.coin) {
    throw StateError('sign-result coin mismatch');
  }
  return decoded;
}

/// Production verification gate. In addition to protocol correlation it
/// proves that the signature belongs to the claimed account and signs the
/// exact raw transaction originally shown by the online wallet.
Future<SignResult> verifySignResultCryptographically(
  Uint8List payload, {
  required SignRequest expected,
  String? expectedSigner,
}) async {
  final result = verifySignResultPayload(payload, expected: expected);
  final chain = chainForCoin(expected.coin);
  final parsed = parseUnsignedTransfer(chain, expected.rawTx);
  final expectedDomain = expected.chainId;
  if (parsed.networkId == null) {
    if (expectedDomain != null) {
      throw StateError('non-EVM sign request must not carry a chainId');
    }
  } else if (expectedDomain == null ||
      parsed.networkId != BigInt.from(expectedDomain)) {
    throw StateError('sign-result transaction chainId mismatch');
  }
  final verified = await verifySignedTransaction(
    chain: chain,
    unsignedTx: expected.rawTx,
    signedTx: result.signedTx,
    claimedSigner: result.signer,
  );
  if (verified.txHash != result.txHash) {
    throw StateError('sign-result transaction hash mismatch');
  }
  if (parsed.from != null &&
      !Addresses.equal(chain, parsed.from!, verified.signer)) {
    throw StateError('sign-result signer does not match transaction sender');
  }
  if (expectedSigner != null &&
      !Addresses.equal(chain, verified.signer, expectedSigner)) {
    throw StateError('sign-result signer does not match paired account');
  }
  return result;
}

// ---- formatting helpers --------------------------------------------------------

String hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// `TQm9xPa2Wc8h…` → `TQm9…3kFa`-style middle truncation for address display.
String truncateMiddle(String value, {int head = 8, int tail = 8}) =>
    value.length <= head + tail
    ? value
    : '${value.substring(0, head)}…${value.substring(value.length - tail)}';
