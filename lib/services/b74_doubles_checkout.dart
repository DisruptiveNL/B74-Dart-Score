/// Dart-by-dart validation for Straight, Double and Master Out.
/// A value is encoded as a board segment: S20, D20, T20, S25 or BULL.
class B74DoublesCheckout {
  static final List<String> segments = [
    for (var n = 1; n <= 20; n++) ...['S$n', 'D$n', 'T$n'],
    'S25',
    'BULL',
  ];

  static int value(String segment) {
    if (segment == 'BULL') return 50;
    if (segment == 'S25') return 25;
    if (segment.length < 2) throw ArgumentError.value(segment);
    final multiplier = switch (segment[0]) {
      'S' => 1,
      'D' => 2,
      'T' => 3,
      _ => throw ArgumentError.value(segment),
    };
    final number = int.tryParse(segment.substring(1));
    if (number == null || number < 1 || number > 20) {
      throw ArgumentError.value(segment);
    }
    return multiplier * number;
  }

  static bool isDouble(String segment) =>
      segment == 'BULL' ||
      (segment.startsWith('D') && segments.contains(segment));

  static bool valid({
    required int remaining,
    required int score,
    required List<String> darts,
    String checkOut = 'double',
  }) {
    if (!{'straight', 'double', 'master'}.contains(checkOut)) {
      throw ArgumentError.value(checkOut, 'checkOut');
    }
    if (darts.isEmpty || darts.length > 3) return false;
    final last = darts.last;
    if (checkOut == 'double' && !isDouble(last)) return false;
    if (checkOut == 'master' &&
        !isDouble(last) &&
        !(last.startsWith('T') && segments.contains(last))) {
      return false;
    }
    var sum = 0;
    for (final dart in darts) {
      try {
        sum += value(dart);
      } on ArgumentError {
        return false;
      }
      if (sum >= remaining && dart != darts.last) return false;
    }
    return sum == score && sum == remaining;
  }
}
