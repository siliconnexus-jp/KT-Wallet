import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:wallet_data/wallet_data.dart' show CustomToken;

import 'history_service.dart';

/// Trust/visibility origin for one asset movement in wallet-wide history.
///
/// This is deliberately separate from transaction confirmation. A confirmed
/// block can contain an unverified or malicious token transfer, and an
/// unconfirmed transaction can still target an official asset.
enum HistoryAssetKind { official, userAdded, unverified, risky }

extension HistoryAssetKindVisibility on HistoryAssetKind {
  bool get visibleInPrimaryHistory =>
      this == HistoryAssetKind.official || this == HistoryAssetKind.userAdded;
}

/// Applies the same final display policy to Gateway and direct history.
///
/// Official identity remains supplied by the strict per-network registry used
/// during history normalization. A user-added identity is accepted only when
/// its exact network id and contract/mint match; symbol and display name are
/// never identities.
HistoryAssetKind classifyHistoryAsset(
  ChainTxRecord record,
  Iterable<CustomToken> customTokens,
) {
  final contract = record.assetContract;
  if (contract == null) return HistoryAssetKind.official;
  if (record.assetVerified) return HistoryAssetKind.official;

  final userAdded = customTokens.any(
    (token) =>
        token.enabled &&
        token.networkId != null &&
        token.networkId == record.networkId &&
        token.contract != null &&
        _sameContract(record.coin, token.contract!, contract),
  );
  if (userAdded) return HistoryAssetKind.userAdded;

  if (record.impersonatesProtectedSymbol ||
      _containsPromotionOrLink(record.assetSymbol)) {
    return HistoryAssetKind.risky;
  }
  return HistoryAssetKind.unverified;
}

bool _sameContract(Coin coin, String expected, String actual) => switch (coin) {
  Coin.eth ||
  Coin.polygon ||
  Coin.base ||
  Coin.arbitrum ||
  Coin.avalanche ||
  Coin.bnb => expected.toLowerCase() == actual.toLowerCase(),
  Coin.tron || Coin.solana => expected == actual,
};

bool _containsPromotionOrLink(String? symbol) {
  if (symbol == null) return false;
  final value = symbol.trim().toLowerCase();
  if (value.isEmpty) return false;
  return value.contains('://') ||
      value.contains('www.') ||
      value.contains('t.me/') ||
      value.contains('.com/') ||
      value.contains('.net/') ||
      value.contains('.org/');
}
