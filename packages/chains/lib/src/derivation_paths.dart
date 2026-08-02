/// Canonical account-zero derivation paths used by the native Wallet Core
/// bridge and AIRGAP-V1 account exports.
///
/// Keep these values in the dependency-free `chains` package so the online
/// wallet and the offline signer cannot silently advertise different paths
/// for the same native key. Trust Wallet Core 4.7.0's `getKeyForCoin` and
/// `getAddressForCoin` use `TWDerivationDefault`; for Solana that is the
/// first registry derivation, `m/44'/501'/0'`.
const evmDefaultDerivationPath = "m/44'/60'/0'/0/0";
const tronDefaultDerivationPath = "m/44'/195'/0'/0/0";
const solanaDefaultDerivationPath = "m/44'/501'/0'";

/// AIRGAP-V1 coin ids to the exact path used to derive their exported key.
/// EVM-compatible networks intentionally share the Ethereum account key.
const accountExportDerivationPaths = <int, String>{
  60: evmDefaultDerivationPath,
  966: evmDefaultDerivationPath,
  8453: evmDefaultDerivationPath,
  42161: evmDefaultDerivationPath,
  9000: evmDefaultDerivationPath,
  714: evmDefaultDerivationPath,
  195: tronDefaultDerivationPath,
  501: solanaDefaultDerivationPath,
};
