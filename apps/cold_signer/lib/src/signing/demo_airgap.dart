import 'dart:convert';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';

/// Canonical demo air-gap traffic for the simulated camera loop.
///
/// The camera itself stays simulated (no capture hardware in this build), but
/// everything else is the real AIRGAP-V1 protocol: the request below is
/// CBOR-encoded, split by the real [Fragmenter] into the exact frames
/// kt_wallet would display, re-parsed frame by frame through
/// [AirgapFrame.decode] + [FrameAggregator], and decoded back via
/// [AirgapPayload.decode].

/// Fixed 8-byte request id. Random-looking but constant so tests are
/// deterministic; its hex prefix 7F3A2C matches the REQ-7F3A2C label used
/// across the design mocks.
final Uint8List demoReqId =
    Uint8List.fromList(const [0x7f, 0x3a, 0x2c, 0x91, 0x5e, 0xd4, 0x08, 0xb6]);

/// Wallet id shared by the demo hot wallet and this demo signer, so the
/// validator's walletId check passes for the canonical request.
const demoWalletId = 'WLT-A1B2C3D4';

/// SLIP-44 coin type for TRON.
const demoCoinTron = 195;

/// The demo signer address (the "from" account shown on C7/C9).
const demoSignerAddress = 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa';

/// Demo recipient shown on the parse screen.
const demoToAddress = 'TWd4qCEUYAJgLtSpQ2dK7wY9nMxR38uQz';

/// USDT's real TRC-20 contract address on TRON mainnet (public knowledge),
/// used so the demo intent looks like genuine traffic.
const demoUsdtContract = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

/// How long the demo hot wallet keeps a request valid.
const demoExpirySeconds = 600;

/// Chunk size for demo traffic. Production uses the [Fragmenter] default
/// (400 bytes/frame); the demo payload is only a few hundred bytes, which
/// would fit in a single frame and never exercise the multi-frame aggregation
/// UI, so the demo shrinks the chunk to get a realistic animated-QR session.
const demoChunkSize = 64;

/// The demo "raw transaction". A production request carries the chain's
/// native encoding (protobuf bytes for TRON); the demo uses the utf8 bytes of
/// this canonical JSON intent so the payload is honest about being simulated
/// while still flowing through the real fragment → aggregate → decode path.
Uint8List demoRawTx() => Uint8List.fromList(utf8.encode(jsonEncode({
      'type': 'trc20_transfer',
      'contract': demoUsdtContract,
      'from': demoSignerAddress,
      'to': demoToAddress,
      'amount': '120000000',
      'decimals': 6,
    })));

/// Display-hint summary, mirroring what kt_wallet would attach (reconciliation
/// only — never a signing input, see payload.dart).
Map<String, Object> demoSummary() => {
      'op': 'Token Transfer（TRC-20）',
      'token': 'USDT',
      'amount': '120.00',
      'rawAmount': '120000000',
      'decimals': 6,
      'from': demoSignerAddress,
      'to': demoToAddress,
    };

/// The canonical demo sign-request: a TRON USDT transfer of 120.00 to
/// [demoToAddress]. Only the timestamps vary (they must sit inside the
/// validator's expiry/clock-skew window); pass [now] to pin them in tests.
SignRequest demoSignRequest({DateTime? now}) {
  final createdAt = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  return SignRequest(
    reqId: demoReqId,
    walletId: demoWalletId,
    coin: demoCoinTron,
    rawTx: demoRawTx(),
    summary: demoSummary(),
    createdAt: createdAt,
    expiresAt: createdAt + demoExpirySeconds,
  );
}

/// The exact ordered frame set kt_wallet's animated QR would emit for the
/// canonical demo request.
List<AirgapFrame> demoSignRequestFrames({DateTime? now}) =>
    Fragmenter(chunkSize: demoChunkSize)
        .fragment(demoSignRequest(now: now).encode(), reqId: demoReqId);

/// Fixed demo transaction hash. NOT a real hash of anything — a deterministic
/// stand-in, since the demo signer holds no private key.
const demoTxHash =
    '5c1f0e6a94d2b7c8130fa6e2d9b45871cc03e9f6a2814d5b7e90c3fa61d82b47';

/// Builds the [SignResult] answering [request]: same reqId/wallet/coin, signed
/// by the demo signer address. The "signedTx" is the request's rawTx followed
/// by a fixed 65-byte pattern standing in for the secp256k1 signature — a real
/// signer would produce the chain's native signed encoding here.
SignResult demoSignResult(SignRequest request) {
  final fakeSignature =
      Uint8List.fromList([for (var i = 0; i < 65; i++) (i * 7 + 13) & 0xff]);
  return SignResult(
    reqId: request.reqId,
    walletId: request.walletId,
    coin: request.coin,
    signedTx: Uint8List.fromList([...request.rawTx, ...fakeSignature]),
    signer: demoSignerAddress,
    txHash: demoTxHash,
  );
}

/// Frame set for a sign-result, ready for the animated result QR.
List<AirgapFrame> demoSignResultFrames(SignResult result) =>
    Fragmenter(chunkSize: demoChunkSize)
        .fragment(result.encode(), reqId: result.reqId);
