import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

BigInt _gwei(int n) => BigInt.from(n) * BigInt.from(1000000000);

void main() {
  group('Eip1559Tx known vectors', () {
    // Expected bytes/hashes computed once with an independent Python
    // reference (own RLP + own Keccak-f[1600], the permutation verified
    // against the published Keccak-f[1600] zero-state vector and the digests
    // against the classic keccak256('') / keccak256('abc') constants).

    test('native 1 ETH transfer locks exact bytes and signing hash', () {
      // chainId=1, nonce=1, maxPriorityFee=2 gwei, maxFee=120 gwei,
      // gas=21000, to=0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
      // value=1e18 wei, data=empty.
      final tx = Eip1559Tx(
        chainId: BigInt.one,
        nonce: BigInt.one,
        maxPriorityFeePerGas: _gwei(2),
        maxFeePerGas: _gwei(120),
        gasLimit: BigInt.from(21000),
        to: Eip1559Tx.addressBytes('0x70997970C51812dc3A010C7d01b50e0d17dc79C8'),
        value: BigInt.parse('1000000000000000000'),
        data: Uint8List(0),
      );
      expect(
        _hex(tx.encodeUnsigned()),
        '02f001018477359400851bf08eb0008252089470997970c51812dc3a010c7d01'
        'b50e0d17dc79c8880de0b6b3a764000080c0',
      );
      expect(
        _hex(tx.signingHash()),
        '1cc71bed16ae6643f9454f055cdf1cb26d5957ed2258a92f0d0aeec3f70b5bcd',
      );
    });

    test('ERC-20 USDT transfer locks exact bytes and signing hash', () {
      // chainId=1, nonce=42, maxPriorityFee=1 gwei, maxFee=80 gwei,
      // gas=65000, to=USDT contract, value=0,
      // data=transfer(0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed, 100e6).
      final tx = Eip1559Tx(
        chainId: BigInt.one,
        nonce: BigInt.from(42),
        maxPriorityFeePerGas: _gwei(1),
        maxFeePerGas: _gwei(80),
        gasLimit: BigInt.from(65000),
        to: Eip1559Tx.addressBytes('0xdAC17F958D2ee523a2206206994597C13D831ec7'),
        value: BigInt.zero,
        data: Erc20.transferCalldata(
          to: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
          amount: BigInt.from(100000000),
        ),
      );
      expect(
        _hex(tx.encodeUnsigned()),
        '02f86d012a843b9aca008512a05f200082fde894dac17f958d2ee523a2206206'
        '994597c13d831ec780b844a9059cbb0000000000000000000000005aaeb6053f'
        '3e94c9b9a09f33669435e7ef1beaed00000000000000000000000000000000000'
        '00000000000000000000005f5e100c0',
      );
      expect(
        _hex(tx.signingHash()),
        'd83488f87371719be29b601f3a5e70a0ebe96950c253eaa275030f06c2f738e8',
      );
    });

    test('contract creation (to=null) + large nonce locks exact bytes', () {
      // chainId=137, nonce=2^64-1, maxPriorityFee=30 gwei, maxFee=300 gwei,
      // gas=1_000_000, to=null, value=0, data=0x600160005401600055.
      final tx = Eip1559Tx(
        chainId: BigInt.from(137),
        nonce: (BigInt.one << 64) - BigInt.one,
        maxPriorityFeePerGas: _gwei(30),
        maxFeePerGas: _gwei(300),
        gasLimit: BigInt.from(1000000),
        to: null,
        value: BigInt.zero,
        data: Uint8List.fromList(
            [0x60, 0x01, 0x60, 0x00, 0x54, 0x01, 0x60, 0x00, 0x55]),
      );
      final encoded = _hex(tx.encodeUnsigned());
      expect(
        encoded,
        '02e8818988ffffffffffffffff8506fc23ac008545d964b800830f4240808089'
        '600160005401600055c0',
      );
      // to=null RLP-encodes as the empty string (0x80) between gasLimit and
      // value: ...830f4240 80 80 89...
      expect(encoded, contains('830f4240808089'));
      expect(
        _hex(tx.signingHash()),
        'a0157bd428a4d668e594d5c6e9f461d5f41044647ef1bacbf26591a69c23ee80',
      );
    });

    test('zero fees, zero value, empty data locks exact bytes', () {
      // chainId=1, nonce=0, both fees 0, gas=21000,
      // to=0x0000000000000000000000000000000000000001, value=0, data=empty.
      final tx = Eip1559Tx(
        chainId: BigInt.one,
        nonce: BigInt.zero,
        maxPriorityFeePerGas: BigInt.zero,
        maxFeePerGas: BigInt.zero,
        gasLimit: BigInt.from(21000),
        to: Eip1559Tx.addressBytes(
            '0x0000000000000000000000000000000000000001'),
        value: BigInt.zero,
        data: Uint8List(0),
      );
      expect(
        _hex(tx.encodeUnsigned()),
        '02df018080808252089400000000000000000000000000000000000000018080c0',
      );
      expect(
        _hex(tx.signingHash()),
        'e2293d9f81073217691fb51b30b163f199787fa57698bbcb19fed8a30d3a3905',
      );
    });

    test('envelope starts with the 0x02 type byte', () {
      final tx = Eip1559Tx(
        chainId: BigInt.one,
        nonce: BigInt.zero,
        maxPriorityFeePerGas: BigInt.zero,
        maxFeePerGas: BigInt.zero,
        gasLimit: BigInt.from(21000),
        to: null,
        value: BigInt.zero,
        data: Uint8List(0),
      );
      expect(tx.encodeUnsigned()[0], Eip1559Tx.txType);
      expect(tx.signingHash().length, 32);
    });
  });

  group('Eip1559Tx validation', () {
    Eip1559Tx build({
      BigInt? chainId,
      BigInt? priority,
      BigInt? maxFee,
      Uint8List? to,
      BigInt? value,
    }) =>
        Eip1559Tx(
          chainId: chainId ?? BigInt.one,
          nonce: BigInt.zero,
          maxPriorityFeePerGas: priority ?? BigInt.zero,
          maxFeePerGas: maxFee ?? BigInt.zero,
          gasLimit: BigInt.from(21000),
          to: to,
          value: value ?? BigInt.zero,
          data: Uint8List(0),
        );

    test('rejects a non-positive chainId', () {
      expect(() => build(chainId: BigInt.zero), throwsArgumentError);
    });

    test('rejects priority fee above max fee', () {
      expect(
        () => build(priority: BigInt.two, maxFee: BigInt.one),
        throwsArgumentError,
      );
    });

    test('rejects a non-20-byte to address', () {
      expect(() => build(to: Uint8List(19)), throwsArgumentError);
    });

    test('rejects a negative value', () {
      expect(() => build(value: BigInt.from(-1)), throwsArgumentError);
    });

    test('addressBytes rejects an EIP-55 checksum mismatch', () {
      // Valid mixed-case address with one letter's case flipped.
      expect(
        () => Eip1559Tx.addressBytes(
            '0x5aaeb6053F3E94C9b9A09f33669435E7Ef1BeAed'),
        throwsArgumentError,
      );
    });
  });

  group('Eip1559Tx.forTransfer', () {
    final fees = (
      chainId: BigInt.one,
      nonce: BigInt.from(7),
      priority: _gwei(2),
      max: _gwei(100),
    );

    test('native transfer: to=recipient, value=amount, empty data', () {
      final intent = TransferIntent(
        chain: Chain.ethereum,
        operation: TxOperation.nativeTransfer,
        from: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        to: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
        amount: Amount.parse('1.5', 18, symbol: 'ETH'),
      );
      final tx = Eip1559Tx.forTransfer(
        intent,
        chainId: fees.chainId,
        nonce: fees.nonce,
        maxPriorityFeePerGas: fees.priority,
        maxFeePerGas: fees.max,
        gasLimit: BigInt.from(21000),
      );
      expect(_hex(tx.to!), '5aaeb6053f3e94c9b9a09f33669435e7ef1beaed');
      expect(tx.value, BigInt.parse('1500000000000000000'));
      expect(tx.data, isEmpty);
    });

    test('token transfer: to=contract, value=0, data=ERC-20 calldata', () {
      final intent = TransferIntent(
        chain: Chain.polygon,
        operation: TxOperation.tokenTransfer,
        from: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
        to: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
        amount: Amount.parse('100', 6, symbol: 'USDT'),
        tokenContract: '0xc2132D05D31c914a87C6611C10748AEb04B58e8F',
        tokenSymbol: 'USDT',
      );
      final tx = Eip1559Tx.forTransfer(
        intent,
        chainId: BigInt.from(137),
        nonce: fees.nonce,
        maxPriorityFeePerGas: fees.priority,
        maxFeePerGas: fees.max,
        gasLimit: BigInt.from(65000),
      );
      expect(_hex(tx.to!), 'c2132d05d31c914a87c6611c10748aeb04b58e8f');
      expect(tx.value, BigInt.zero);
      expect(
        _hex(tx.data),
        _hex(Erc20.transferCalldata(
          to: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
          amount: BigInt.from(100000000),
        )),
      );
    });

    test('rejects a non-EVM intent', () {
      final intent = TransferIntent(
        chain: Chain.tron,
        operation: TxOperation.nativeTransfer,
        from: 'Tfrom',
        to: 'Tto',
        amount: Amount.parse('1', 6, symbol: 'TRX'),
      );
      expect(
        () => Eip1559Tx.forTransfer(
          intent,
          chainId: fees.chainId,
          nonce: fees.nonce,
          maxPriorityFeePerGas: fees.priority,
          maxFeePerGas: fees.max,
          gasLimit: BigInt.from(21000),
        ),
        throwsArgumentError,
      );
    });
  });
}
