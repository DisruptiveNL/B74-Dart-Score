/// Predefined X01 match formats offered in the setup screen.
///
/// These are pure UI presets that only fill the underlying [legs]/[sets]
/// values (which the game stores and treats as "first to"); they are not
/// persisted themselves. [MatchFormat.custom] lets the user pick legs and sets
/// freely up to [kMaxLegs]/[kMaxSets].
library;

/// Maximum selectable legs (first-to, per set) for a custom X01 match.
const int kMaxLegs = 9;

/// Maximum selectable sets (first-to) for a custom X01 match.
const int kMaxSets = 9;

/// Standard X01 match formats, expressed via "Best of" naming where applicable.
///
/// Real darts formats come in two flavours: pure leg races (one set) and set
/// formats. A "Best of N legs" race is won by the first player to reach
/// (N + 1) / 2 legs, which is exactly the value stored in [MatchFormat.legs].
enum MatchFormat {
  /// Best of 3 legs (first to 2).
  bo3,

  /// Best of 5 legs (first to 3), the default matching the previous standard.
  bo5,

  /// Best of 7 legs (first to 4).
  bo7,

  /// Best of 9 legs (first to 5).
  bo9,

  /// PDC set format: best of 5 sets (first to 3), each set best of 5 legs
  /// (first to 3).
  pdcSets,

  /// Premier League leg race: first to 6 legs, no sets.
  premierLeague,

  /// User-defined legs and sets via steppers.
  custom,
}

/// Reverse lookup from stored legs/sets back to a named preset.
extension MatchFormatLookup on MatchFormat {
  /// The preset whose legs/sets equal [legs]/[sets], or [MatchFormat.custom]
  /// when no named preset matches. Used to label past games in the history,
  /// which only persist the numeric legs/sets.
  static MatchFormat fromValues(int legs, int sets) {
    for (final f in MatchFormat.values) {
      if (f != MatchFormat.custom && f.legs == legs && f.sets == sets) {
        return f;
      }
    }
    return MatchFormat.custom;
  }
}

/// Numeric legs/sets each preset maps onto.
extension MatchFormatValues on MatchFormat {
  /// First-to legs (per set) for this preset, or `null` for [MatchFormat.custom]
  /// where the value comes from the stepper.
  int? get legs => switch (this) {
    MatchFormat.bo3 => 2,
    MatchFormat.bo5 => 3,
    MatchFormat.bo7 => 4,
    MatchFormat.bo9 => 5,
    MatchFormat.pdcSets => 3,
    MatchFormat.premierLeague => 6,
    MatchFormat.custom => null,
  };

  /// First-to sets for this preset, or `null` for [MatchFormat.custom].
  int? get sets => switch (this) {
    MatchFormat.pdcSets => 3,
    MatchFormat.custom => null,
    _ => 1,
  };
}
