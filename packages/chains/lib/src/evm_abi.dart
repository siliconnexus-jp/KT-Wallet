import 'dart:typed_data';

import 'address.dart';
import 'keccak.dart';

/// Minimal ABI encoding for the only EVM contract call V1 builds: ERC-20
/// `transfer(address,uint256)` (detailed-design.md §4.2). Pure and testable;
/// the wallet-core SigningInput that carries this calldata is assembled on the
/// native side (P1-4).
abstract final class Erc20 {
  /// 4-byte selector of `transfer(address,uint256)` = 0xa9059cbb.
  static Uint8List get transferSelector => Uint8List.sublistView(
    keccak256('transfer(address,uint256)'.codeUnits),
    0,
    4,
  );

  /// 4-byte selector of `approve(address,uint256)` = 0x095ea7b3.
  static Uint8List get approveSelector => Uint8List.sublistView(
    keccak256('approve(address,uint256)'.codeUnits),
    0,
    4,
  );

  /// Builds the 68-byte calldata for an ERC-20 transfer.
  /// [to] is a 0x-prefixed 20-byte hex address; [amount] is the raw token
  /// amount in base units.
  ///
  /// The recipient goes through the same [Addresses.validate] gate as native
  /// transfers: a mistyped mixed-case address fails EIP-55 here rather than
  /// sending tokens to an address nobody holds the key for. (Native transfers
  /// were already covered via `Eip1559Tx.addressBytes`; token transfers used
  /// to bypass every check but the byte length.)
  static Uint8List transferCalldata({
    required String to,
    required BigInt amount,
  }) {
    if (amount < BigInt.zero) {
      throw ArgumentError('amount must be non-negative');
    }
    final check = Addresses.validate(Chain.ethereum, to);
    if (!check.isValid) {
      throw ArgumentError('invalid recipient address: ${check.reason ?? to}');
    }
    final addr = _hexToBytes(to);
    if (addr.length != 20) {
      throw ArgumentError('to must be a 20-byte address');
    }
    final out = BytesBuilder();
    out.add(transferSelector);
    // address left-padded to 32 bytes.
    out.add(Uint8List(12));
    out.add(addr);
    // uint256 big-endian, left-padded to 32 bytes.
    out.add(_uint256(amount));
    return out.toBytes();
  }

  /// Builds the only ERC-20 approval mutation KT Wallet permits:
  /// `approve(spender, 0)`. There is deliberately no public arbitrary-amount
  /// encoder, which keeps both online construction and offline parsing on the
  /// same zero-allowance whitelist.
  static Uint8List revokeApprovalCalldata({required String spender}) {
    final check = Addresses.validate(Chain.ethereum, spender);
    if (!check.isValid) {
      throw ArgumentError(
        'invalid spender address: ${check.reason ?? spender}',
      );
    }
    final addr = _hexToBytes(spender);
    if (addr.length != 20) {
      throw ArgumentError('spender must be a 20-byte address');
    }
    final out = BytesBuilder();
    out.add(approveSelector);
    out.add(Uint8List(12));
    out.add(addr);
    out.add(Uint8List(32));
    return out.toBytes();
  }

  static Uint8List _uint256(BigInt v) {
    if (v >= (BigInt.one << 256)) {
      throw ArgumentError('amount exceeds uint256');
    }
    final bytes = Uint8List(32);
    var x = v;
    final mask = BigInt.from(0xFF);
    for (var i = 31; i >= 0 && x > BigInt.zero; i--) {
      bytes[i] = (x & mask).toInt();
      x = x >> 8;
    }
    return bytes;
  }

  static Uint8List _hexToBytes(String hex) {
    var h = hex;
    if (h.startsWith('0x') || h.startsWith('0X')) h = h.substring(2);
    if (h.length.isOdd) throw ArgumentError('odd-length hex');
    return Uint8List.fromList([
      for (var i = 0; i < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ]);
  }
}
