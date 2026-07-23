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
      Chain.tron => 195,
      Chain.solana => 501,
    };

Chain chainForCoin(int coin) => switch (coin) {
      60 => Chain.ethereum,
      966 => Chain.polygon,
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
      _ => null,
    };

String addressForChain(ChainAddresses addresses, Chain chain) => switch (chain) {
      Chain.ethereum => addresses.eth,
      Chain.polygon => addresses.polygon,
      Chain.tron => addresses.tron,
      Chain.solana => addresses.solana,
    };

// ---- demo fee schedule ------------------------------------------------------

/// Demo fee schedule per chain: (slow, standard, fast) in the native unit.
/// Static tiers at current fidelity — a live fee oracle replaces this later.
Amount networkFeeFor(Chain chain, int feeTier) {
  final (tiers, decimals, symbol) = switch (chain) {
    Chain.tron => (('6.8', '13.7', '27.4'), 6, 'TRX'),
    Chain.ethereum => (('0.00021', '0.00042', '0.00084'), 18, 'ETH'),
    Chain.polygon => (('0.01', '0.02', '0.04'), 18, 'POL'),
    Chain.solana => (('0.000005', '0.00001', '0.00002'), 9, 'SOL'),
  };
  final value = switch (feeTier) { 0 => tiers.$1, 2 => tiers.$3, _ => tiers.$2 };
  return Amount.parse(value, decimals, symbol: symbol);
}

/// Builds the confirm-screen preview from the draft via the chains types.
/// maxFee == networkFee at current fidelity (static demo schedule).
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
  decimals: 6,
  recipient: 'TWd4qCEUf3aVpXe2HKk9gJt6nMxR38uQz',
  amount: Amount.parse('120.00', 6, symbol: 'USDT'),
  feeTier: 1,
  tokenContract: usdtTronContract,
);

const demoWalletId = 'WLT-91A4C7';
const demoFromAddress = 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa';

/// Fixed demo reqId — its first three bytes render as the design's
/// `REQ-7F3A2C` label, and being constant keeps the demo QR golden-stable.
final Uint8List demoReqId =
    Uint8List.fromList(const [0x7F, 0x3A, 0x2C, 0x91, 0x5D, 0x08, 0xB4, 0xE6]);

/// Fixed demo timestamp (2026-01-01T00:00:00Z) for golden determinism.
const demoCreatedAtSec = 1767225600;

// ---- sign-request construction ----------------------------------------------

Uint8List randomReqId() {
  final rng = Random.secure();
  return Uint8List.fromList(
      List.generate(AirgapLimits.reqIdLength, (_) => rng.nextInt(256)));
}

/// Expiry window for a displayed sign-request (well under
/// [AirgapLimits.maxExpirySeconds]).
const signRequestTtlSeconds = 600;

/// Raw transaction bytes for the sign request.
///
/// EVM chains carry a REAL typed transaction: `0x02 || rlp(...)` unsigned
/// EIP-1559 bytes from the chains package (native transfer or ERC-20
/// `transfer` calldata) — exactly what a signer hashes and signs. The
/// optional [nonce] / [maxPriorityFeePerGas] / [maxFeePerGas] overrides
/// carry live chain-state parameters (ChainParamsService); when absent the
/// documented DEMO constants apply, so every demo/golden rendering stays
/// byte-identical. The optional [evmChainId] carries the ACTIVE network's
/// signing-domain id (testnets: Sepolia 11155111, Amoy 80002) — absent, the
/// mainnet [chainIdForChain] constants apply, and a wrong-network signature
/// is invalid by construction, which is exactly the isolation we want. TRON
/// (protobuf) and Solana (message v0) still use the canonical-JSON
/// placeholder pending real-signing integration to validate their encoders
/// against.
Uint8List rawTxFor(
  TransferDraft draft, {
  required String from,
  BigInt? nonce,
  BigInt? maxPriorityFeePerGas,
  BigInt? maxFeePerGas,
  int? evmChainId,
}) {
  if (draft.chain == Chain.ethereum || draft.chain == Chain.polygon) {
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
      gasLimit: BigInt.from(draft.operation == TxOperation.nativeTransfer ? 21000 : 65000),
    );
    return tx.encodeUnsigned();
  }
  return _jsonRawTx(draft, from: from);
}

/// Deterministic placeholder raw transaction for chains whose real
/// serialization isn't integrated yet (TRON protobuf, Solana message):
/// utf8 of the canonical JSON of the transfer intent.
Uint8List _jsonRawTx(TransferDraft draft, {required String from}) =>
    Uint8List.fromList(utf8.encode(json.encode({
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
    })));

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
  int? evmChainId,
  String? networkLabel,
}) {
  final live = draft != null;
  final d = draft ?? demoDraft;
  final created =
      nowEpochSeconds ?? (live ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : demoCreatedAtSec);
  final id = walletId.length > AirgapLimits.maxWalletId
      ? walletId.substring(0, AirgapLimits.maxWalletId)
      : walletId;
  return SignRequest(
    reqId: reqId ?? (live ? randomReqId() : demoReqId),
    walletId: id,
    coin: coinForChain(d.chain),
    // Non-EVM chains have no signing-domain id; EVM chains carry the active
    // network's (defaulting to mainnet).
    chainId:
        chainIdForChain(d.chain) == null ? null : (evmChainId ?? chainIdForChain(d.chain)),
    rawTx: rawTxFor(
      d,
      from: fromAddress,
      nonce: nonce,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      maxFeePerGas: maxFeePerGas,
      evmChainId: evmChainId,
    ),
    summary: {
      SummaryKeys.network: networkLabel ?? d.networkLabel,
      SummaryKeys.amount: d.amountText,
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
List<String> encodeQrFrames(AirgapPayload payload, {required Uint8List reqId}) => [
      for (final frame in Fragmenter(chunkSize: airgapChunkSize)
          .fragment(payload.encode(), reqId: reqId))
        base64Url.encode(frame.encode()),
    ];

// ---- sign-result (simulated signer) -------------------------------------------

/// What the Cold Signer would answer for [request]. The signature bytes and
/// tx hash are deterministic demo values derived from the request (the camera
/// — and the signer's key — stay simulated); everything around them is the
/// genuine AIRGAP-V1 encoding.
SignResult buildDemoSignResult(SignRequest request, {required String signer}) {
  final signedTx =
      Uint8List.fromList([...utf8.encode('SIGNED-V1:'), ...request.rawTx]);
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
SignResult decodeSignResultFrames(List<String> qrFrames, {required SignRequest expected}) {
  final aggregator = FrameAggregator();
  for (final qr in qrFrames) {
    aggregator.addFrame(AirgapFrame.decode(base64Url.decode(qr)));
    if (aggregator.state == AggregatorState.done) break;
  }
  if (aggregator.state != AggregatorState.done) {
    throw StateError('incomplete frame set: ${aggregator.state}'
        '${aggregator.failure == null ? '' : ' (${aggregator.failure})'}');
  }
  return verifySignResultPayload(aggregator.payload!, expected: expected);
}

/// Decodes an assembled payload as a [SignResult] and verifies it answers
/// [expected] — the shared tail of [decodeSignResultFrames], also used by the
/// live camera path where frames arrive one by one instead of as a list.
SignResult verifySignResultPayload(Uint8List payload, {required SignRequest expected}) {
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

// ---- formatting helpers --------------------------------------------------------

String hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// `TQm9xPa2Wc8h…` → `TQm9…3kFa`-style middle truncation for address display.
String truncateMiddle(String value, {int head = 8, int tail = 8}) =>
    value.length <= head + tail
        ? value
        : '${value.substring(0, head)}…${value.substring(value.length - tail)}';
