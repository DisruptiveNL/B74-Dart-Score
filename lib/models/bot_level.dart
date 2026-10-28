/// The skill tiers a computer opponent can play at, weakest first.
///
/// The index is what the `players.bot_level` column stores, so the order is
/// part of the schema: never reorder or remove a value, only append. A null
/// column is a human player.
///
/// Each bot is one player row that every game against it shares, numbered
/// within its tier from one up so that a game can hold two of the same
/// strength. Its name and uuid are fixed here rather than generated. The uuid
/// is shaped like the random ones but sits in a range no generator produces,
/// and it is the same on every device: a bot row never travels over sync,
/// but a backup restored on another device must not leave two rows for one
/// bot behind.
enum BotLevel {
  rookie,
  amateur,
  semiPro,
  pro,
  legend;

  /// The neutral name stored in the player row of this tier's first bot.
  /// Deliberately not localized: the row outlives the language setting. What
  /// the screen shows comes from `label(l)`, never from here.
  String get storedName => switch (this) {
    BotLevel.rookie => 'Bot Rookie',
    BotLevel.amateur => 'Bot Amateur',
    BotLevel.semiPro => 'Bot Semi-Pro',
    BotLevel.pro => 'Bot Pro',
    BotLevel.legend => 'Bot Legend',
  };

  /// The stored name of the bot numbered [ordinal] in this tier: the first
  /// carries the bare tier name, the rest their number.
  String storedNameFor(int ordinal) =>
      ordinal == 1 ? storedName : '$storedName $ordinal';

  /// The fixed uuid of this tier's first bot, identical on every device.
  String get uuid => uuidFor(1);

  /// The fixed uuid of the bot numbered [ordinal] in this tier. The first
  /// bot's uuid predates the numbering and is kept as it was, so the number
  /// is written one below itself.
  String uuidFor(int ordinal) =>
      '00000000-0000-4000-8000-'
      '${(ordinal - 1).toString().padLeft(9, '0')}'
      'b${index.toString().padLeft(2, '0')}';
}
