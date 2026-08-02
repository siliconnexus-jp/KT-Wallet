import 'package:chains/chains.dart' show Addresses, Chain;

class KnownRecipientAddress {
  const KnownRecipientAddress({required this.address, required this.label});

  final String address;
  final String label;
}

class RecipientLookalikeRisk {
  const RecipientLookalikeRisk({required this.candidate, required this.known});

  final String candidate;
  final KnownRecipientAddress known;
}

/// Detects a classic clipboard/address-poisoning pattern: a valid recipient
/// has the same human-visible prefix and suffix as a saved/recent address, but
/// differs in the middle.
///
/// Exact matches are safe. Invalid or cross-chain addresses are ignored. This
/// is deliberately a local heuristic rather than a green "safe" verdict; no
/// local rule can prove that an arbitrary new address is trustworthy.
RecipientLookalikeRisk? detectRecipientLookalike({
  required Chain chain,
  required String candidate,
  required Iterable<KnownRecipientAddress> knownAddresses,
}) {
  final checked = Addresses.validate(chain, candidate.trim());
  if (!checked.isValid) return null;
  final normalizedCandidate = _normalize(
    chain,
    checked.normalized ?? candidate,
  );
  final edgeLength = _isEvm(chain) ? 6 : 5;
  if (normalizedCandidate.length < edgeLength * 2 + 1) return null;

  for (final known in knownAddresses) {
    final knownCheck = Addresses.validate(chain, known.address.trim());
    if (!knownCheck.isValid) continue;
    final normalizedKnown = _normalize(
      chain,
      knownCheck.normalized ?? known.address,
    );
    if (normalizedKnown == normalizedCandidate) continue;
    if (normalizedKnown.length != normalizedCandidate.length) continue;
    if (normalizedKnown.startsWith(
          normalizedCandidate.substring(0, edgeLength),
        ) &&
        normalizedKnown.endsWith(
          normalizedCandidate.substring(
            normalizedCandidate.length - edgeLength,
          ),
        )) {
      return RecipientLookalikeRisk(
        candidate: normalizedCandidate,
        known: known,
      );
    }
  }
  return null;
}

bool _isEvm(Chain chain) => switch (chain) {
  Chain.ethereum ||
  Chain.polygon ||
  Chain.base ||
  Chain.arbitrum ||
  Chain.avalanche ||
  Chain.bnb => true,
  Chain.tron || Chain.solana => false,
};

String _normalize(Chain chain, String address) {
  final trimmed = address.trim();
  return _isEvm(chain) ? trimmed.toLowerCase() : trimmed;
}
