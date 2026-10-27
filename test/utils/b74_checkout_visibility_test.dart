import 'package:dartscore_app/models/dart_throw.dart';
import 'package:dartscore_app/utils/b74_checkout_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

DartThrow visit({String? hitsJson, int checkoutDarts = 0}) => DartThrow(
  gameId: 1,
  playerId: 1,
  score: 60,
  dartsUsed: 3,
  leg: 1,
  set: 1,
  remainingBefore: 100,
  thrownAt: DateTime(2026, 10, 27),
  hitsJson: hitsJson,
  checkoutDarts: checkoutDarts,
);

void main() {
  test('no visits does not imply a measurable double percentage', () {
    expect(hasCompleteDartCheckoutData([]), isFalse);
  });
  test('numeric visit cannot support exact double stats even on checkout', () {
    expect(hasCompleteDartCheckoutData([visit(checkoutDarts: 1)]), isFalse);
  });
  test('fully recorded individual dart visits support detailed stats', () {
    expect(
      hasCompleteDartCheckoutData([
        visit(hitsJson: '[{"f":20,"m":3}]'),
        visit(hitsJson: '[{"f":20,"m":1}]'),
      ]),
      isTrue,
    );
  });
  test('mixed numeric and dart-by-dart history hides detailed stats', () {
    expect(
      hasCompleteDartCheckoutData([
        visit(hitsJson: '[{"f":20,"m":3}]'),
        visit(),
      ]),
      isFalse,
    );
  });
}
