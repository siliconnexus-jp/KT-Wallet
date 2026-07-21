import 'dart:math';

/// Demo-grade mnemonic generation for the Cold Signer.
///
/// HONEST LIMITS: this is NOT BIP-39. The real BIP-39 wordlist + checksum live
/// behind core_crypto's native MethodChannel backend, which does not exist in
/// this offline demo build (and MethodChannels are unavailable in widget
/// tests). Instead the signer draws 12 independent words from the 256-word
/// list below with a CSPRNG ([Random.secure] by default), giving
/// 12 × log2(256) = 96 bits of entropy — no checksum word. A production build
/// must replace [generateMnemonic] with core_crypto's generateMnemonic().
///
/// 256 unique words (verified by test): lowercase ASCII, 3–9 letters. The
/// first row is the canned demo mnemonic used by the design snapshots, so
/// gallery distractor words are always drawable from this list too.
const signerWordlist = <String>[
  'ripple', 'canyon', 'script', 'harbor', 'velvet', 'noble', 'orbit', 'meadow',
  'signal', 'pledge', 'quartz', 'ember', 'acorn', 'amber', 'anchor', 'anvil',
  'apron', 'arrow', 'aspen', 'atlas', 'autumn', 'badge', 'bamboo', 'barrel',
  'basil', 'beacon', 'berry', 'birch', 'bishop', 'blaze', 'bloom', 'bluff',
  'breeze', 'brick', 'bridge', 'bronze', 'brook', 'bubble', 'buckle', 'butter',
  'cabin', 'cactus', 'camel', 'candle', 'carbon', 'cargo', 'carol', 'castle',
  'cedar', 'cellar', 'chalk', 'cherry', 'chisel', 'cider', 'cinder', 'citrus',
  'cliff', 'clover', 'cobalt', 'comet', 'compass', 'copper', 'coral', 'cotton',
  'cradle', 'crater', 'crayon', 'cricket', 'crystal', 'cypress', 'dagger', 'daisy',
  'dawn', 'delta', 'denim', 'diesel', 'dome', 'drift', 'dune', 'eagle',
  'echo', 'elbow', 'elder', 'engine', 'falcon', 'fable', 'feather', 'fern',
  'fiddle', 'flint', 'fossil', 'galaxy', 'garnet', 'geyser', 'ginger', 'glacier',
  'goose', 'granite', 'grape', 'gravel', 'grove', 'hazel', 'heron', 'hollow',
  'honey', 'horizon', 'iceberg', 'indigo', 'iris', 'ivory', 'jasper', 'jungle',
  'juniper', 'kettle', 'kite', 'lagoon', 'lantern', 'lava', 'lemon', 'lily',
  'linen', 'lobster', 'locket', 'lotus', 'lumber', 'magnet', 'mango', 'maple',
  'marble', 'marsh', 'mellow', 'mirror', 'molten', 'mosaic', 'moss', 'mustang',
  'nectar', 'nickel', 'north', 'nutmeg', 'oasis', 'ocean', 'olive', 'onyx',
  'opal', 'osprey', 'otter', 'oyster', 'paddle', 'pantry', 'parcel', 'pebble',
  'pecan', 'pepper', 'petal', 'pigeon', 'pine', 'pistol', 'planet', 'plum',
  'pocket', 'polar', 'pollen', 'poppy', 'prairie', 'prism', 'pulley', 'pumpkin',
  'quill', 'raft', 'rattle', 'raven', 'reef', 'ribbon', 'ridge', 'river',
  'rocket', 'rustic', 'saddle', 'saffron', 'sage', 'salmon', 'sandal', 'sapphire',
  'satchel', 'scarlet', 'shadow', 'shore', 'silver', 'sketch', 'sleigh', 'slope',
  'socket', 'sonar', 'sparrow', 'spice', 'spruce', 'squash', 'stable', 'stereo',
  'stone', 'summit', 'sunset', 'swan', 'tablet', 'tandem', 'tannery', 'teapot',
  'temple', 'thistle', 'thunder', 'tiger', 'timber', 'toffee', 'token', 'torch',
  'trellis', 'trout', 'tulip', 'tundra', 'turbine', 'turnip', 'twilight', 'umber',
  'urchin', 'valley', 'vanilla', 'vapor', 'vault', 'verse', 'vessel', 'violet',
  'vista', 'wagon', 'walnut', 'walrus', 'warden', 'waffle', 'willow', 'winter',
  'wisdom', 'wolf', 'wonder', 'yarrow', 'zephyr', 'zinc', 'acre', 'alpine',
  'badger', 'bramble', 'candela', 'cascade', 'ledger', 'mason', 'cove', 'fjord',
];

/// Draws a [wordCount]-word mnemonic from [signerWordlist]. Pass a seeded
/// [random] in tests; the app uses [Random.secure].
List<String> generateMnemonic({Random? random, int wordCount = 12}) {
  final rng = random ?? Random.secure();
  return List.generate(
      wordCount, (_) => signerWordlist[rng.nextInt(signerWordlist.length)]);
}

/// [count] distinct distractor words, none equal to (or duplicating) the
/// [correct] word — option fodder for the mnemonic verification quiz.
List<String> drawDistractors(String correct, int count, {Random? random}) {
  final rng = random ?? Random.secure();
  final picked = <String>{};
  while (picked.length < count) {
    final w = signerWordlist[rng.nextInt(signerWordlist.length)];
    if (w != correct) picked.add(w);
  }
  return picked.toList();
}
