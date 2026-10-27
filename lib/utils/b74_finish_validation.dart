import '../models/game.dart';

/// Whether an X01 checkout can be completed with exactly [dartsUsed] darts.
/// Earlier darts may miss; the final dart must satisfy the checkout mode.
/// This validates feasibility, not the actual fields thrown.
bool b74CanFinishInDarts(int remaining, int dartsUsed, CheckoutMode mode) {
  if (remaining <= 0 || dartsUsed < 1 || dartsUsed > 3) return false;
  final scores = <int>{0, 25, 50};
  for (var n = 1; n <= 20; n++) {
    scores.addAll([n, n * 2, n * 3]);
  }
  final finishes = switch (mode) {
    CheckoutMode.straightOut => scores.where((s) => s > 0).toSet(),
    CheckoutMode.doubleOut => <int>{50, for (var n = 1; n <= 20; n++) n * 2},
    CheckoutMode.masterOut => <int>{
      50,
      for (var n = 1; n <= 20; n++) n * 2,
      for (var n = 1; n <= 20; n++) n * 3,
    },
  };
  var prefixes = <int>{0};
  for (var dart = 1; dart <= dartsUsed; dart++) {
    if (dart == dartsUsed) {
      return prefixes.any((prefix) => finishes.contains(remaining - prefix));
    }
    prefixes = {
      for (final prefix in prefixes)
        for (final score in scores) prefix + score,
    };
  }
  return false;
}
