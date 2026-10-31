import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_checkout.dart';

void main() {
  test('double and bull are legal checkout endings', () {
    expect(
      B74DoublesCheckout.valid(remaining: 40, score: 40, darts: ['D20']),
      isTrue,
    );
    expect(
      B74DoublesCheckout.valid(remaining: 50, score: 50, darts: ['BULL']),
      isTrue,
    );
    expect(
      B74DoublesCheckout.valid(
        remaining: 101,
        score: 101,
        darts: ['T17', 'BULL'],
      ),
      isTrue,
    );
  });
  test('rejects singles, triples, mismatched and premature finishes', () {
    expect(
      B74DoublesCheckout.valid(remaining: 20, score: 20, darts: ['S20']),
      isFalse,
    );
    expect(
      B74DoublesCheckout.valid(remaining: 60, score: 60, darts: ['T20']),
      isFalse,
    );
    expect(
      B74DoublesCheckout.valid(remaining: 40, score: 40, darts: ['D10']),
      isFalse,
    );
    expect(
      B74DoublesCheckout.valid(remaining: 40, score: 40, darts: ['D20', 'D1']),
      isFalse,
    );
    expect(
      B74DoublesCheckout.valid(remaining: 50, score: 50, darts: ['S25', 'S25']),
      isFalse,
    );
  });
  test('validates all board segments', () {
    expect(B74DoublesCheckout.value('T20'), 60);
    expect(B74DoublesCheckout.value('S25'), 25);
    expect(() => B74DoublesCheckout.value('D21'), throwsArgumentError);
  });
}
