import 'dart:async';

import 'package:chains/rpc.dart';

import '../../l10n/app_localizations.dart';
import '../market/gateway_client.dart';

enum FeeQuoteFailure { unavailable, rateLimited, network }

FeeQuoteFailure classifyFeeQuoteFailure(Object error) {
  if ((error is GatewayException && error.isRateLimited) ||
      (error is RpcException && (error.code == 429 || error.code == 403))) {
    return FeeQuoteFailure.rateLimited;
  }
  if (error is GatewayTransportException || error is TimeoutException) {
    return FeeQuoteFailure.network;
  }
  return FeeQuoteFailure.unavailable;
}

String feeQuoteFailureLabel(FeeQuoteFailure failure, AppLocalizations l10n) =>
    switch (failure) {
      FeeQuoteFailure.rateLimited => l10n.feeRateLimited,
      FeeQuoteFailure.network => l10n.feeNetworkUnavailable,
      FeeQuoteFailure.unavailable => l10n.feeUnavailable,
    };
