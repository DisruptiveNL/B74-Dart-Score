import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/utils/b74_checkout_opportunities.dart';
import 'package:flutter_test/flutter_test.dart';

DartThrow visit(int remaining, int score, {bool bust = false}) => DartThrow(
  gameId: 1,
  playerId: 1,
  score: score,
  dartsUsed: 3,
  leg: 1,
  set: 1,
  remainingBefore: remaining,
  thrownAt: DateTime(2026, 10, 27),
  bust: bust,
);

void main() {
  test('B74 double-out opportunity boundaries and bogey numbers', () {
    for (final n in [2, 40, 100, 158, 160, 161, 164, 167, 170]) {
      expect(isB74CheckoutOpportunity(n), isTrue, reason: '$n');
    }
    for (final n in [0, 1, 171, 180, 501, 159, 162, 163, 165, 166, 168, 169]) {
      expect(isB74CheckoutOpportunity(n), isFalse, reason: '$n');
    }
  });

  test('counts theoretical chances even when no double is attempted', () {
    final stats = B74CheckoutStats.fromThrows([
      visit(501, 100), // outside checkout range
      visit(156, 60),  // opportunity, even without dart-level data
      visit(96, 0, bust: true), // bust is still an opportunity
      visit(96, 96), // successful finish
      visit(159, 0), // bogey number
    ]);
    expect(stats.opportunities, 3);
    expect(stats.finishes, 1);
    expect(stats.rate, closeTo(33.333333, 0.001));
  });

  test('zero opportunities gives zero percent, never NaN', () {
    final stats = B74CheckoutStats.fromThrows([visit(501, 180)]);
    expect(stats.opportunities, 0);
    expect(stats.finishes, 0);
    expect(stats.rate, 0);
  });
}
