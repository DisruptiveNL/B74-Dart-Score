import '../models/dart_throw.dart';

/// B74 competition rule: a theoretical three-dart double-out opportunity
/// exists when the visit starts at 2..170, except the seven bogey numbers.
/// This does not assert that a dart was actually thrown at a double.
bool isB74CheckoutOpportunity(int remainingBefore) =>
    remainingBefore >= 2 &&
    remainingBefore <= 170 &&
    !const {159, 162, 163, 165, 166, 168, 169}.contains(remainingBefore);

/// A numeric-input-friendly measure, independent of per-dart hit data.
/// Each committed visit counts at most once, including a bust.
class B74CheckoutStats {
  final int opportunities;
  final int finishes;

  const B74CheckoutStats({required this.opportunities, required this.finishes});

  double get rate => opportunities == 0 ? 0 : finishes / opportunities * 100;

  factory B74CheckoutStats.fromThrows(Iterable<DartThrow> throws) {
    var opportunities = 0;
    var finishes = 0;
    for (final visit in throws) {
      if (!isB74CheckoutOpportunity(visit.remainingBefore)) continue;
      opportunities++;
      if (!visit.bust && visit.remainingBefore - visit.score == 0) {
        finishes++;
      }
    }
    return B74CheckoutStats(opportunities: opportunities, finishes: finishes);
  }
}
