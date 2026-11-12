/// C1B11 — wedstrijdreglement v1. Onafhankelijk van Flutter en database.
/// Een wedstrijd bewaart een eigen JSON-kopie van deze configuratie.
class B74CompetitionReglement {
  static const startPolicies = {'fixedAway', 'fixedHome', 'bull'};
  static const checkIns = {'straight', 'double'};
  static const checkOuts = {'straight', 'double', 'master'};
  static const bestOfOptions = {3, 5, 7, 9, 11};

  static Map<String, dynamic> defaults() => {
    'version': 1,
    'singles': _group(score: 501, bestOf: 5),
    'doubles': _group(score: 701, bestOf: 5),
    'beer': _group(score: 1001, bestOf: 1),
  };

  static Map<String, dynamic> _group({
    required int score,
    required int bestOf,
  }) => {
    'startingScore': score,
    'bestOf': bestOf,
    'checkIn': 'straight',
    'checkOut': 'double',
    'startPolicy': 'fixedAway',
    'bullDecidingLeg': false,
    'winPoints': 1,
  };

  /// Converts persisted legacy DOGD rules without mutating the old record.
  static Map<String, dynamic> fromLegacy(Map<String, dynamic> legacy) {
    final result = defaults();
    final singles = Map<String, dynamic>.from(result['singles'] as Map);
    final doubles = Map<String, dynamic>.from(result['doubles'] as Map);
    final beer = Map<String, dynamic>.from(result['beer'] as Map);
    for (final group in [singles, doubles, beer]) {
      group['checkOut'] = legacy['checkOut'] ?? 'double';
      group['startPolicy'] = legacy['startPolicy'] ?? 'fixedAway';
      group['bullDecidingLeg'] = legacy['bullDecidingLeg'] ?? false;
    }
    beer['bullDecidingLeg'] = false;
    singles['startingScore'] = legacy['startingScore'] ?? 501;
    singles['bestOf'] = legacy['bestOf'] ?? 5;
    singles['checkIn'] = legacy['checkIn'] ?? 'straight';
    doubles['bestOf'] = legacy['couplesBestOf'] ?? 5;
    doubles['checkIn'] = legacy['doublesCheckIn'] ?? singles['checkIn'];
    beer['checkIn'] = legacy['beerCheckIn'] ?? singles['checkIn'];
    result['singles'] = singles;
    result['doubles'] = doubles;
    result['beer'] = beer;
    validate(result);
    return result;
  }

  static void validate(Map<String, dynamic> rules) {
    if (rules['version'] != 1)
      throw const FormatException('Ongeldige reglementversie');
    const scores = {
      'singles': {301, 501, 701},
      'doubles': {301, 501, 701},
      'beer': {301, 501, 701, 1001},
    };
    for (final kind in ['singles', 'doubles', 'beer']) {
      final raw = rules[kind];
      if (raw is! Map) throw FormatException('Ontbrekend reglement: $kind');
      final group = Map<String, dynamic>.from(raw);
      if (!scores[kind]!.contains(group['startingScore'])) {
        throw FormatException('Ongeldige startscore: $kind');
      }
      final bestOf = group['bestOf'];
      if (kind == 'beer' ? bestOf != 1 : !bestOfOptions.contains(bestOf)) {
        throw FormatException('Ongeldige Best of: $kind');
      }
      if (!checkIns.contains(group['checkIn']) ||
          !checkOuts.contains(group['checkOut'])) {
        throw FormatException('Ongeldige in/out: $kind');
      }
      if (!startPolicies.contains(group['startPolicy'])) {
        throw FormatException('Ongeldige startregeling: $kind');
      }
      if (group['bullDecidingLeg'] is! bool ||
          (kind == 'beer' && group['bullDecidingLeg'] != false)) {
        throw FormatException('Ongeldige beslissende-leg-bull: $kind');
      }
      if (group['winPoints'] is! int || (group['winPoints'] as int) < 1) {
        throw FormatException('Wedstrijdpunten minimaal 1: $kind');
      }
    }
  }

  /// Index 0..3 for Singles/Koppels, 0 for Biergame.
  /// A bullstart requires an explicit bull winner and returns null here.
  static String? firstLegStarter(
    Map<String, dynamic> rules,
    String kind,
    int index,
  ) {
    validate(rules);
    if (!{'singles', 'doubles', 'beer'}.contains(kind))
      throw ArgumentError.value(kind);
    if (index < 0 || (kind == 'beer' ? index != 0 : index > 3)) {
      throw RangeError.value(index);
    }
    final group = Map<String, dynamic>.from(rules[kind] as Map);
    final policy = group['startPolicy'];
    if (policy == 'bull') return null;
    final away = policy == 'fixedAway';
    return (index.isEven == away) ? 'away' : 'home';
  }
}
