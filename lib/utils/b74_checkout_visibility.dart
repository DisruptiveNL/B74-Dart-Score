import '../models/dart_throw.dart';

/// Detailed checkout/double rates require a complete dart-by-dart record.
/// Numeric visit input stores only a total; it cannot prove how many darts
/// were actually aimed at a double. Mixed histories are also not complete.
/// This is deliberately conservative: unknown is not 0%.
bool hasCompleteDartCheckoutData(Iterable<DartThrow> visits) {
  var seen = false;
  for (final visit in visits) {
    seen = true;
    if (visit.hitsJson == null || visit.hitsJson!.isEmpty) return false;
  }
  return seen;
}
