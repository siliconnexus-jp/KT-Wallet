/// Shared closed-schema helpers for display-only wallet caches.
///
/// A cache is not a source of transaction authority, but it is still a local
/// trust boundary: ambiguous or malformed content must never be rendered as a
/// verified balance or transaction. Callers reject the entire snapshot when
/// any helper throws.
Map<String, Object?> requireExactSnapshotObject(
  Object? value, {
  required Set<String> members,
}) {
  if (value is! Map || value.length != members.length) {
    throw const FormatException('snapshot object schema mismatch');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || !members.contains(key)) {
      throw const FormatException('snapshot object has unknown member');
    }
    result[key] = entry.value;
  }
  return result;
}

String requireBoundedSnapshotText(
  Object? value, {
  required int maxChars,
  bool allowEmpty = false,
}) {
  if (value is! String ||
      (!allowEmpty && value.isEmpty) ||
      value.length > maxChars ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw const FormatException('snapshot text is invalid');
  }
  return value;
}

String? requireNullableSnapshotText(Object? value, {required int maxChars}) =>
    value == null
    ? null
    : requireBoundedSnapshotText(value, maxChars: maxChars);

int requireSnapshotEpochMillis(Object? value) {
  // This cache format was introduced after Unix epoch and is intentionally
  // bounded to year 2100 to reject integer resource abuse before DateTime
  // construction. A future format version can extend the range explicitly.
  const latest = 4102444800000;
  if (value is! int || value < 0 || value > latest) {
    throw const FormatException('snapshot timestamp is invalid');
  }
  return value;
}
