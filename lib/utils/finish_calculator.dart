import '../models/game.dart';

/// Returns checkout suggestions for a given remaining score and checkout mode.
class FinishCalculator {
  // ── Double-Out routes ─────────────────────────────────────────────────────
  // All routes end with a Double or Bull (50). Includes previously-missing
  // odd numbers 3–19 (achievable via S+D combinations).
  static const _checkoutsDouble = <int, List<List<String>>>{
    170: [['T20', 'T20', 'Bull']],
    167: [['T20', 'T19', 'Bull']],
    164: [['T20', 'T18', 'Bull']],
    161: [['T20', 'T17', 'Bull']],
    160: [['T20', 'T20', 'D20']],
    158: [['T20', 'T20', 'D19']],
    157: [['T20', 'T19', 'D20']],
    156: [['T20', 'T20', 'D18']],
    155: [['T20', 'T19', 'D19']],
    154: [['T20', 'T18', 'D20']],
    153: [['T20', 'T19', 'D18']],
    152: [['T20', 'T20', 'D16']],
    151: [['T20', 'T17', 'D20']],
    150: [['T20', 'T18', 'D18']],
    149: [['T20', 'T19', 'D16']],
    148: [['T20', 'T20', 'D14']],
    147: [['T20', 'T17', 'D18']],
    146: [['T20', 'T18', 'D16']],
    145: [['T20', 'T15', 'D20']],
    144: [['T20', 'T20', 'D12']],
    143: [['T20', 'T17', 'D16']],
    142: [['T20', 'T14', 'D20']],
    141: [['T20', 'T19', 'D12']],
    140: [['T20', 'T20', 'D10']],
    139: [['T20', 'T13', 'D20']],
    138: [['T20', 'T18', 'D12']],
    137: [['T20', 'T19', 'D10']],
    136: [['T20', 'T20', 'D8']],
    135: [['T20', 'T17', 'D12']],
    134: [['T20', 'T14', 'D16']],
    133: [['T20', 'T19', 'D8']],
    132: [['T20', 'T16', 'D12']],
    131: [['T20', 'T13', 'D16']],
    130: [['T20', 'T18', 'D8']],
    129: [['T19', 'T16', 'D12']],
    128: [['T20', 'T20', 'D4']],
    127: [['T20', 'T17', 'D8']],
    126: [['T19', 'T19', 'D6']],
    125: [['T20', 'T15', 'D10'], ['25', 'T20', 'D20']],
    124: [['T20', 'T16', 'D8']],
    123: [['T19', 'T16', 'D9']],
    122: [['T18', 'T18', 'D7'], ['T18', 'T20', 'D4']],
    121: [['T20', 'T11', 'D14']],
    120: [['T20', 'S20', 'D20']],
    119: [['T19', 'T12', 'D13']],
    118: [['T20', 'S18', 'D20']],
    117: [['T20', 'S17', 'D20']],
    116: [['T20', 'S16', 'D20']],
    115: [['T20', 'S15', 'D20']],
    114: [['T20', 'S14', 'D20']],
    113: [['T20', 'S13', 'D20']],
    112: [['T20', 'S12', 'D20']],
    111: [['T20', 'S11', 'D20']],
    110: [['T20', 'S10', 'D20'], ['T20', 'Bull']],
    109: [['T20', 'S9', 'D20']],
    108: [['T20', 'S8', 'D20']],
    107: [['T19', 'S10', 'D20'], ['T19', 'Bull']],
    106: [['T20', 'S6', 'D20']],
    105: [['T20', 'S5', 'D20']],
    104: [['T20', 'S4', 'D20']],
    103: [['T20', 'S3', 'D20']],
    102: [['T20', 'S2', 'D20']],
    101: [['T20', 'S1', 'D20'], ['T17', 'Bull']],
    100: [['T20', 'D20']],
    99:  [['T19', 'S10', 'D16']],
    98:  [['T20', 'D19']],
    97:  [['T19', 'D20']],
    96:  [['T20', 'D18']],
    95:  [['T19', 'D19'], ['Bull', 'S5', 'D20']],
    94:  [['T18', 'D20']],
    93:  [['T19', 'D18']],
    92:  [['T20', 'D16']],
    91:  [['T17', 'D20']],
    90:  [['T18', 'D18'], ['T20', 'D15']],
    89:  [['T19', 'D16']],
    88:  [['T20', 'D14']],
    87:  [['T17', 'D18']],
    86:  [['T18', 'D16']],
    85:  [['T15', 'D20']],
    84:  [['T20', 'D12']],
    83:  [['T17', 'D16']],
    82:  [['T14', 'D20'], ['Bull', 'D16']],
    81:  [['T19', 'D12'], ['T15', 'D18']],
    80:  [['T20', 'D10'], ['D20', 'D20']],
    79:  [['T19', 'D11'], ['T13', 'D20']],
    78:  [['T18', 'D12']],
    77:  [['T19', 'D10'], ['T15', 'D16']],
    76:  [['T20', 'D8']],
    75:  [['T17', 'D12'], ['T15', 'D15']],
    74:  [['T14', 'D16']],
    73:  [['T19', 'D8'], ['T11', 'D20']],
    72:  [['T16', 'D12'], ['T20', 'D6']],
    71:  [['T13', 'D16']],
    70:  [['T18', 'D8'], ['T10', 'D20']],
    69:  [['T19', 'D6'], ['T11', 'D18']],
    68:  [['T20', 'D4']],
    67:  [['T17', 'D8'], ['T9', 'D20']],
    66:  [['T10', 'D18'], ['T14', 'D12']],
    65:  [['T19', 'D4'], ['T11', 'D16'], ['25', 'D20']],
    64:  [['T16', 'D8'], ['T14', 'D11']],
    63:  [['T13', 'D12'], ['T17', 'D6']],
    62:  [['T10', 'D16'], ['T12', 'D13']],
    61:  [['T15', 'D8'], ['T11', 'D14']],
    60:  [['S20', 'D20']],
    59:  [['S19', 'D20']],
    58:  [['S18', 'D20']],
    57:  [['S17', 'D20']],
    56:  [['T16', 'D4'], ['S16', 'D20']],
    55:  [['S15', 'D20'], ['S19', 'D18']],
    54:  [['S14', 'D20'], ['S18', 'D18']],
    53:  [['S13', 'D20'], ['S17', 'D18']],
    52:  [['S12', 'D20'], ['T12', 'D8']],
    51:  [['S11', 'D20'], ['S19', 'D16']],
    50:  [['S10', 'D20'], ['Bull']],
    49:  [['S9', 'D20'], ['S17', 'D16']],
    48:  [['S16', 'D16'], ['S8', 'D20']],
    47:  [['S15', 'D16'], ['S7', 'D20']],
    46:  [['S14', 'D16'], ['S6', 'D20']],
    45:  [['S13', 'D16'], ['S5', 'D20']],
    44:  [['S12', 'D16'], ['S4', 'D20']],
    43:  [['S11', 'D16'], ['S3', 'D20']],
    42:  [['S10', 'D16'], ['S2', 'D20']],
    41:  [['S9', 'D16'], ['S1', 'D20']],
    40:  [['D20']],
    39:  [['S7', 'D16']],
    38:  [['D19']],
    37:  [['S5', 'D16']],
    36:  [['D18']],
    35:  [['S3', 'D16']],
    34:  [['D17']],
    33:  [['S1', 'D16'], ['S17', 'D8']],
    32:  [['D16']],
    31:  [['S15', 'D8']],
    30:  [['D15']],
    29:  [['S13', 'D8']],
    28:  [['D14']],
    27:  [['S11', 'D8']],
    26:  [['D13']],
    25:  [['S9', 'D8']],
    24:  [['D12']],
    23:  [['S7', 'D8']],
    22:  [['D11']],
    21:  [['S5', 'D8'], ['S9', 'D6']],
    20:  [['D10']],
    19:  [['S3', 'D8'], ['S1', 'D9']],   // previously missing
    18:  [['D9']],
    17:  [['S1', 'D8'], ['S3', 'D7']],   // previously missing
    16:  [['D8']],
    15:  [['S7', 'D4'], ['S1', 'D7']],   // previously missing
    14:  [['D7']],
    13:  [['S5', 'D4'], ['S1', 'D6']],   // previously missing
    12:  [['D6']],
    11:  [['S3', 'D4'], ['S1', 'D5']],   // previously missing
    10:  [['D5']],
    9:   [['S1', 'D4'], ['S3', 'D3']],   // previously missing
    8:   [['D4']],
    7:   [['S3', 'D2'], ['S1', 'D3']],   // previously missing
    6:   [['D3']],
    5:   [['S1', 'D2'], ['S3', 'D1']],   // previously missing
    4:   [['D2']],
    3:   [['S1', 'D1']],                  // previously missing
    2:   [['D1']],
  };

  // ── Straight-Out extra routes ──────────────────────────────────────────────
  // Any dart can finish (single, double, triple). Adds 1-dart single finishes
  // for scores impossible or suboptimal in double-out.
  static const _checkoutsStraight = <int, List<List<String>>>{
    1:  [['S1']],
    2:  [['S2']],   // simpler than D1 for beginners
    3:  [['S3'], ['T1']],
    4:  [['S4']],
    5:  [['S5']],
    6:  [['S6'], ['T2']],
    7:  [['S7']],
    8:  [['S8']],
    9:  [['S9'], ['T3']],
    10: [['S10']],
    11: [['S11']],
    12: [['S12'], ['T4']],
    13: [['S13']],
    14: [['S14']],
    15: [['S15'], ['T5']],
    16: [['S16']],
    17: [['S17']],
    18: [['S18'], ['T6']],
    19: [['S19']],
    20: [['S20'], ['D10']],  // S20 is 1 dart (simpler than D10 for some)
    21: [['T7']],
    24: [['T8']],
    27: [['T9']],
    30: [['T10']],
    33: [['T11']],
    36: [['T12']],
    39: [['T13']],
    42: [['T14']],
    45: [['T15']],
    48: [['T16']],
    51: [['T17']],
    54: [['T18']],
    57: [['T19']],
    60: [['T20']],
  };

  // ── Master-Out extra routes ────────────────────────────────────────────────
  // Finish with Double OR Triple. Adds 1-dart triple finishes (T1–T20).
  static const _checkoutsMaster = <int, List<List<String>>>{
    3:  [['T1']],
    6:  [['T2']],
    9:  [['T3']],
    12: [['T4']],
    15: [['T5']],
    18: [['T6']],
    21: [['T7']],
    24: [['T8']],
    27: [['T9']],
    30: [['T10']],
    33: [['T11']],
    36: [['T12']],
    39: [['T13']],
    42: [['T14']],
    45: [['T15']],
    48: [['T16']],
    51: [['T17']],
    54: [['T18']],
    57: [['T19']],
    60: [['T20']],
  };

  // ── Favorite-double-oriented routes ─────────────────────────────────────────

  /// Maps a favorite-double label (`D1`-`D20` or `Bull`) to its point value
  /// (2-40, or 50 for `Bull`). Returns null for any other label.
  static int? _doubleValue(String label) {
    if (label == 'Bull') return 50;
    if (label.startsWith('D')) {
      final n = int.tryParse(label.substring(1));
      if (n != null && n >= 1 && n <= 20) return n * 2;
    }
    return null;
  }

  /// Returns the dart notation for a single dart scoring exactly [value]
  /// points (1-60), preferring a single, then bull, then triple, then
  /// double. Returns null if no single dart can score [value].
  static String? _singleDartLabel(int value) {
    if (value <= 0) return null;
    if (value >= 1 && value <= 20) return 'S$value';
    if (value == 25) return '25';
    if (value == 50) return 'Bull';
    if (value % 3 == 0 && value <= 60) return 'T${value ~/ 3}';
    if (value % 2 == 0 && value <= 40) return 'D${value ~/ 2}';
    return null;
  }

  /// Finds a 1- or 2-dart combination scoring exactly [value] points,
  /// trying the largest first dart first. Returns null if [value] cannot be
  /// reached with at most 2 darts.
  static List<String>? _leadRoute(int value) {
    if (value <= 0 || value > 120) return null;
    final single = _singleDartLabel(value);
    if (single != null) return [single];
    for (var first = 60; first >= 1; first--) {
      final firstLabel = _singleDartLabel(first);
      if (firstLabel == null) continue;
      final secondLabel = _singleDartLabel(value - first);
      if (secondLabel != null) return [firstLabel, secondLabel];
    }
    return null;
  }

  /// Returns a route to [remaining] that finishes on [favoriteDouble], using
  /// at most 3 darts in total, or null if no such route exists.
  static List<String>? _favoriteDoubleRoute(
    int remaining,
    String favoriteDouble,
  ) {
    final favVal = _doubleValue(favoriteDouble);
    if (favVal == null) return null;
    final lead = _leadRoute(remaining - favVal);
    if (lead == null) return null;
    return [...lead, favoriteDouble];
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Whether a dart on [field] (25 = bull) with [multiplier] may be the one
  /// that takes the rest to zero under [checkoutMode]. A dart that reaches zero
  /// any other way is a bust.
  ///
  /// Master out accepts the single bull as well as the double, the same reading
  /// [canFinishWithOneDart] takes, and no triple of the bull exists to accept.
  static bool finishesOn(
      int field, int multiplier, CheckoutMode checkoutMode) {
    switch (checkoutMode) {
      case CheckoutMode.straightOut:
        return true;
      case CheckoutMode.doubleOut:
        return multiplier == 2;
      case CheckoutMode.masterOut:
        return field == 25
            ? multiplier != 3
            : (multiplier == 2 || multiplier == 3);
    }
  }

  /// Whether a rest of [remaining] above zero can still be finished under
  /// [checkoutMode]. A rest of one cannot, except straight out, so a dart that
  /// leaves it is a bust.
  static bool canStillFinish(int remaining, CheckoutMode checkoutMode) =>
      remaining > 1 || (remaining == 1 && checkoutMode == CheckoutMode.straightOut);

  /// Whether [remaining] can be taken to exactly zero by a single dart that is
  /// also a valid finish under [checkoutMode].
  ///
  /// This is what makes a visit a checkout attempt: the player is one dart away
  /// from the leg. Deliberately arithmetic rather than a lookup in the route
  /// tables above, because those tables list the routes worth suggesting, not
  /// every legal one. Master-out finishes 25 on the single bull, for instance,
  /// but no table carries that as a route because nobody would recommend it.
  static bool canFinishWithOneDart(
    int remaining, [
    CheckoutMode checkoutMode = CheckoutMode.doubleOut,
  ]) {
    if (remaining <= 0) return false;

    final isDouble = remaining <= 40 && remaining.isEven;
    final isTriple = remaining <= 60 && remaining % 3 == 0;
    final isSingle = remaining <= 20;

    switch (checkoutMode) {
      case CheckoutMode.straightOut:
        return isSingle || isDouble || isTriple || remaining == 25 || remaining == 50;
      case CheckoutMode.doubleOut:
        return isDouble || remaining == 50;
      case CheckoutMode.masterOut:
        // Bull counts as a double, the outer bull as a single, and master-out
        // accepts either, so both 25 and 50 finish.
        return isDouble || isTriple || remaining == 25 || remaining == 50;
    }
  }

  /// Returns [primary, alternative?] checkout routes for [remaining], filtered
  /// to routes of at most [maxDarts] darts and valid for [checkoutMode].
  /// [primary] ends with [favoriteDouble] if a matching route exists.
  static ({List<String>? primary, List<String>? alternative}) getRoutes(
    int remaining,
    String? favoriteDouble, {
    int maxDarts = 3,
    CheckoutMode checkoutMode = CheckoutMode.doubleOut,
  }) {
    if (remaining <= 0 || remaining > 170) {
      return (primary: null, alternative: null);
    }
    // Score of 1: only straight-out can finish (S1).
    if (remaining == 1 && checkoutMode != CheckoutMode.straightOut) {
      return (primary: null, alternative: null);
    }

    // Base double-out routes
    final base = (_checkoutsDouble[remaining] ?? [])
        .where((r) => r.length <= maxDarts)
        .toList();

    // Mode-specific extras
    List<List<String>> extras = const [];
    switch (checkoutMode) {
      case CheckoutMode.straightOut:
        extras = (_checkoutsStraight[remaining] ?? [])
            .where((r) => r.length <= maxDarts)
            .toList();
      case CheckoutMode.masterOut:
        extras = (_checkoutsMaster[remaining] ?? [])
            .where((r) => r.length <= maxDarts)
            .toList();
      case CheckoutMode.doubleOut:
        break;
    }

    // Merge extras first (they tend to be shorter/simpler), then base routes.
    // Deduplicate and sort shortest-first.
    final seen = <String>{};
    final all  = <List<String>>[];
    for (final r in [...extras, ...base]) {
      if (seen.add(r.join('|'))) all.add(r);
    }
    all.sort((a, b) => a.length.compareTo(b.length));

    if (all.isEmpty) {
      // No route fits within maxDarts this turn. Still offer a route toward
      // the favorite double (up to 3 darts) as a hint for the next visit.
      final favRoute = (favoriteDouble != null && favoriteDouble.isNotEmpty)
          ? _favoriteDoubleRoute(remaining, favoriteDouble)
          : null;
      return (primary: null, alternative: favRoute);
    }

    // Select primary (preferred) and alternative routes.
    List<String>? primary;
    List<String>? alternative;

    if (favoriteDouble != null && favoriteDouble.isNotEmpty) {
      primary = all.firstWhere(
        (r) => r.last == favoriteDouble,
        orElse: () => [],
      );
      if (primary.isEmpty) primary = null;

      alternative = all.firstWhere(
        (r) => r != primary,
        orElse: () => [],
      );
      if (alternative.isEmpty) alternative = null;

      if (primary == null) {
        primary     = all.first;
        alternative = all.length > 1 ? all[1] : null;

        // Primary doesn't finish on the favorite double, so offer a dedicated
        // route there instead of the next-best alternative.
        final favRoute = _favoriteDoubleRoute(remaining, favoriteDouble);
        if (favRoute != null && favRoute.join('|') != primary.join('|')) {
          alternative = favRoute;
        }
      }
    } else {
      primary     = all.first;
      alternative = all.length > 1 ? all[1] : null;
    }

    return (primary: primary, alternative: alternative);
  }

  /// Legacy helper: keep existing callers working.
  static List<List<String>> getCheckouts(
    int remaining,
    List<String> favoriteDoubles,
  ) {
    final fav = favoriteDoubles.isNotEmpty ? favoriteDoubles.first : null;
    final r = getRoutes(remaining, fav);
    return [
      if (r.primary != null) r.primary!,
      if (r.alternative != null) r.alternative!,
    ];
  }
}
