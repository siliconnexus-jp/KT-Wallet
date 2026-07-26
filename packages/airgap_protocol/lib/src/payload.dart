import 'dart:convert';
import 'dart:typed_data';

import 'cbor.dart';

/// AIRGAP-V1 payload types and their CBOR (de)serialization + strict schema
/// validation (detailed-design.md §3.1). Field keys are integers to keep the
/// encoded size small.

const int airgapVersion = 1;

/// Field-length / count limits (DD §3.1). Enforced on decode.
class AirgapLimits {
  static const maxWalletId = 32;
  static const maxWalletName = 64;
  static const maxAddress = 128;
  static const maxPath = 64;
  static const minAccounts = 1;
  static const maxAccounts = 8;
  static const maxRawTx = 32 * 1024;
  static const maxSignedTx = 34 * 1024;
  static const reqIdLength = 8;
  static const maxExpirySeconds = 3600;
}

enum PayloadType {
  accountExport(1),
  signRequest(2),
  signResult(3);

  const PayloadType(this.wire);
  final int wire;

  static PayloadType fromWire(int v) => switch (v) {
        1 => PayloadType.accountExport,
        2 => PayloadType.signRequest,
        3 => PayloadType.signResult,
        _ => throw PayloadError('unknown payload type $v'),
      };
}

class PayloadError implements Exception {
  PayloadError(this.message);
  final String message;
  @override
  String toString() => 'PayloadError: $message';
}

sealed class AirgapPayload {
  PayloadType get type;
  Uint8List encode();

  /// Decodes and validates any AIRGAP-V1 payload. Throws [PayloadError] on any
  /// schema violation or unknown/mismatched version.
  static AirgapPayload decode(Uint8List bytes) {
    final Object? root;
    try {
      root = cborDecode(bytes);
    } on CborError catch (e) {
      throw PayloadError('malformed CBOR: ${e.message}');
    }
    if (root is! Map) throw PayloadError('payload root must be a map');
    final map = root;
    final version = _int(map, 0, 'version');
    if (version != airgapVersion) {
      throw PayloadError('unsupported version $version');
    }
    final type = PayloadType.fromWire(_int(map, 1, 'type'));
    return switch (type) {
      PayloadType.accountExport => AccountExport._fromMap(map),
      PayloadType.signRequest => SignRequest._fromMap(map),
      PayloadType.signResult => SignResult._fromMap(map),
    };
  }
}

// ---- helpers ---------------------------------------------------------------

int _int(Map<Object?, Object?> m, int key, String name) {
  final v = m[key];
  if (v is! int) throw PayloadError('$name must be an int');
  return v;
}

int? _intOrNull(Map<Object?, Object?> m, int key) {
  final v = m[key];
  if (v == null) return null;
  if (v is! int) throw PayloadError('field $key must be an int');
  return v;
}

String _text(Map<Object?, Object?> m, int key, String name, int maxLen) {
  final v = m[key];
  if (v is! String) throw PayloadError('$name must be text');
  // Limits are on-wire UTF-8 byte lengths, not UTF-16 code units, so multibyte
  // characters can't slip a field past its cap.
  if (utf8.encode(v).length > maxLen) {
    throw PayloadError('$name exceeds $maxLen bytes');
  }
  return v;
}

Uint8List _bytes(Map<Object?, Object?> m, int key, String name, int maxLen) {
  final v = m[key];
  if (v is! Uint8List) throw PayloadError('$name must be bytes');
  if (v.length > maxLen) throw PayloadError('$name exceeds $maxLen');
  return v;
}

Uint8List? _bytesOrNull(
  Map<Object?, Object?> m,
  int key,
  String name,
  int maxLen,
) {
  if (m[key] == null) return null;
  return _bytes(m, key, name, maxLen);
}

// ---- account-export --------------------------------------------------------

class AccountRecord {
  AccountRecord({
    required this.coin,
    required this.address,
    required this.path,
    required this.index,
    this.publicKey,
  });
  final int coin;
  final String address;
  final String path;
  final int index;
  final Uint8List? publicKey;
}

class AccountExport extends AirgapPayload {
  AccountExport({
    required this.walletId,
    required this.walletName,
    required this.accounts,
  }) {
    if (accounts.length < AirgapLimits.minAccounts ||
        accounts.length > AirgapLimits.maxAccounts) {
      throw PayloadError('accounts count out of range');
    }
  }

  final String walletId;
  final String walletName;
  final List<AccountRecord> accounts;

  @override
  PayloadType get type => PayloadType.accountExport;

  @override
  Uint8List encode() => cborEncode({
        0: airgapVersion,
        1: type.wire,
        2: walletId,
        3: walletName,
        4: [
          for (final a in accounts)
            {
              0: a.coin,
              1: a.address,
              2: a.path,
              3: a.index,
              if (a.publicKey != null) 4: a.publicKey,
            },
        ],
      });

  static AccountExport _fromMap(Map<Object?, Object?> m) {
    final rawAccounts = m[4];
    if (rawAccounts is! List) throw PayloadError('accounts must be a list');
    if (rawAccounts.length < AirgapLimits.minAccounts ||
        rawAccounts.length > AirgapLimits.maxAccounts) {
      throw PayloadError('accounts count out of range');
    }
    return AccountExport(
      walletId: _text(m, 2, 'walletId', AirgapLimits.maxWalletId),
      walletName: _text(m, 3, 'walletName', AirgapLimits.maxWalletName),
      accounts: [
        for (final a in rawAccounts)
          if (a is Map)
            AccountRecord(
              coin: _int(a, 0, 'coin'),
              address: _text(a, 1, 'address', AirgapLimits.maxAddress),
              path: _text(a, 2, 'path', AirgapLimits.maxPath),
              index: _int(a, 3, 'index'),
              publicKey: _bytesOrNull(a, 4, 'publicKey', 65),
            )
          else
            throw PayloadError('account entry must be a map'),
      ],
    );
  }
}

// ---- sign-request ----------------------------------------------------------

class SignRequest extends AirgapPayload {
  SignRequest({
    required this.reqId,
    required this.walletId,
    required this.coin,
    this.chainId,
    required this.rawTx,
    this.summary,
    required this.createdAt,
    required this.expiresAt,
  }) {
    if (reqId.length != AirgapLimits.reqIdLength) {
      throw PayloadError('reqId must be ${AirgapLimits.reqIdLength} bytes');
    }
    if (rawTx.length > AirgapLimits.maxRawTx) {
      throw PayloadError('rawTx too large');
    }
    if (expiresAt > createdAt + AirgapLimits.maxExpirySeconds) {
      throw PayloadError('expiry window too long');
    }
    if (expiresAt < createdAt) {
      throw PayloadError('expiresAt before createdAt');
    }
  }

  final Uint8List reqId;
  final String walletId;
  final int coin;
  final int? chainId;
  final Uint8List rawTx;

  /// Reconciliation-only display hint. NOT a signing input (DD §3.4 step 5).
  final Map<Object?, Object?>? summary;
  final int createdAt;
  final int expiresAt;

  String get reqIdHex =>
      reqId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  PayloadType get type => PayloadType.signRequest;

  @override
  Uint8List encode() => cborEncode({
        0: airgapVersion,
        1: type.wire,
        2: reqId,
        3: walletId,
        4: coin,
        if (chainId != null) 5: chainId,
        6: rawTx,
        if (summary != null) 7: summary,
        8: createdAt,
        9: expiresAt,
      });

  static SignRequest _fromMap(Map<Object?, Object?> m) {
    final summary = m[7];
    if (summary != null && summary is! Map) {
      throw PayloadError('summary must be a map');
    }
    return SignRequest(
      reqId: _bytes(m, 2, 'reqId', AirgapLimits.reqIdLength),
      walletId: _text(m, 3, 'walletId', AirgapLimits.maxWalletId),
      coin: _int(m, 4, 'coin'),
      chainId: _intOrNull(m, 5),
      rawTx: _bytes(m, 6, 'rawTx', AirgapLimits.maxRawTx),
      summary: summary as Map<Object?, Object?>?,
      createdAt: _int(m, 8, 'createdAt'),
      expiresAt: _int(m, 9, 'expiresAt'),
    );
  }
}

// ---- sign-result -----------------------------------------------------------

class SignResult extends AirgapPayload {
  SignResult({
    required this.reqId,
    required this.walletId,
    required this.coin,
    required this.signedTx,
    required this.signer,
    required this.txHash,
  }) {
    if (reqId.length != AirgapLimits.reqIdLength) {
      throw PayloadError('reqId must be ${AirgapLimits.reqIdLength} bytes');
    }
    if (signedTx.length > AirgapLimits.maxSignedTx) {
      throw PayloadError('signedTx too large');
    }
  }

  final Uint8List reqId;
  final String walletId;
  final int coin;
  final Uint8List signedTx;
  final String signer;
  final String txHash;

  String get reqIdHex =>
      reqId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  PayloadType get type => PayloadType.signResult;

  @override
  Uint8List encode() => cborEncode({
        0: airgapVersion,
        1: type.wire,
        2: reqId,
        3: walletId,
        4: coin,
        5: signedTx,
        6: signer,
        7: txHash,
      });

  static SignResult _fromMap(Map<Object?, Object?> m) => SignResult(
        reqId: _bytes(m, 2, 'reqId', AirgapLimits.reqIdLength),
        walletId: _text(m, 3, 'walletId', AirgapLimits.maxWalletId),
        coin: _int(m, 4, 'coin'),
        signedTx: _bytes(m, 5, 'signedTx', AirgapLimits.maxSignedTx),
        signer: _text(m, 6, 'signer', AirgapLimits.maxAddress),
        txHash: _text(m, 7, 'txHash', AirgapLimits.maxAddress),
      );
}
