import '../models/game.dart';
import 'dartboard_geometry.dart';
import 'finish_calculator.dart';

/// Where a bot aims its next dart in an X01 leg.
///
/// The choice follows the checkout table rather than a rule of its own, so
/// that the bot sets up and finishes the way the finish suggestion tells a
/// person to, under the same check-out rule. [remaining] is the score before
/// this dart, [dartsLeft] how many darts the visit still has including this
/// one, and [checkedIn] whether the player has already opened under a
/// check-in rule that needs it.
///
/// The order of the rules:
/// 1. Not yet checked in: the double 20, or the triple 20 under master-in,
///    since a triple opens there as well and scores more.
/// 2. A score one dart finishes under the rule: that dart, straight from
///    `canFinishWithOneDart`, since the table leaves out the finishes nobody
///    would recommend to a person, such as 25 on the outer bull under
///    master-out, and a bot at the oche takes what is there.
/// 3. A finish within the darts left: its first dart.
/// 4. A finish that needs more darts than the visit has left: its first dart
///    all the same, which sets the next visit up on the number the table
///    prefers.
/// 5. Everything else, from the numbers above 170 to the handful in the 160s
///    that no three darts finish: the triple 20.
BoardHit x01Target({
  required int remaining,
  required int dartsLeft,
  required bool checkedIn,
  CheckoutMode checkOut = CheckoutMode.doubleOut,
  GameMode checkIn = GameMode.straightIn,
}) {
  if (!checkedIn && checkIn != GameMode.straightIn) {
    return checkIn == GameMode.masterIn
        ? (field: 20, multiplier: 3)
        : (field: 20, multiplier: 2);
  }

  if (FinishCalculator.canFinishWithOneDart(remaining, checkOut)) {
    return _oneDartFinish(remaining, checkOut);
  }

  final within = FinishCalculator.getRoutes(
    remaining,
    null,
    maxDarts: dartsLeft,
    checkoutMode: checkOut,
  );
  if (within.primary != null) return _parseLabel(within.primary!.first);

  final setup = FinishCalculator.getRoutes(
    remaining,
    null,
    checkoutMode: checkOut,
  );
  if (setup.primary != null) return _parseLabel(setup.primary!.first);

  return (field: 20, multiplier: 3);
}

/// The one dart that takes out [remaining] under [checkOut], for a score
/// `canFinishWithOneDart` has already approved. A double is preferred where
/// the rule allows more than one ring, because it is the ring the player is
/// used to finishing on.
BoardHit _oneDartFinish(int remaining, CheckoutMode checkOut) {
  if (remaining == 50) return (field: 25, multiplier: 2);
  if (remaining == 25) return (field: 25, multiplier: 1);
  if (checkOut == CheckoutMode.straightOut && remaining <= 20) {
    return (field: remaining, multiplier: 1);
  }
  if (remaining.isEven && remaining <= 40) {
    return (field: remaining ~/ 2, multiplier: 2);
  }
  return (field: remaining ~/ 3, multiplier: 3);
}

/// Turns a checkout table label such as `T20`, `D16`, `S8`, `25` or `Bull`
/// into the field and ring it names.
BoardHit _parseLabel(String label) {
  if (label == 'Bull') return (field: 25, multiplier: 2);
  if (label == '25') return (field: 25, multiplier: 1);
  final multiplier = switch (label[0]) {
    'T' => 3,
    'D' => 2,
    _ => 1,
  };
  return (field: int.parse(label.substring(1)), multiplier: multiplier);
}
