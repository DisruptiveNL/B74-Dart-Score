import 'package:dartscore_app/services/b74_doubles_checkout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy default remains double out', () {
    expect(B74DoublesCheckout.valid(remaining: 20, score: 20, darts: ['S20']), isFalse);
    expect(B74DoublesCheckout.valid(remaining: 40, score: 40, darts: ['D20']), isTrue);
  });
  test('straight out accepts single, triple and bull', () {
    for (final segment in ['S20', 'T20', 'BULL']) {
      expect(B74DoublesCheckout.valid(remaining: B74DoublesCheckout.value(segment), score: B74DoublesCheckout.value(segment), darts: [segment], checkOut: 'straight'), isTrue);
    }
  });
  test('master out requires double, triple or bull', () {
    expect(B74DoublesCheckout.valid(remaining: 60, score: 60, darts: ['T20'], checkOut: 'master'), isTrue);
    expect(B74DoublesCheckout.valid(remaining: 50, score: 50, darts: ['BULL'], checkOut: 'master'), isTrue);
    expect(B74DoublesCheckout.valid(remaining: 20, score: 20, darts: ['S20'], checkOut: 'master'), isFalse);
  });
  test('all modes reject premature finish, invalid segments and wrong sum', () {
    for (final mode in ['straight', 'double', 'master']) {
      expect(B74DoublesCheckout.valid(remaining: 40, score: 40, darts: ['D20', 'S1'], checkOut: mode), isFalse);
      expect(B74DoublesCheckout.valid(remaining: 40, score: 39, darts: ['D20'], checkOut: mode), isFalse);
      expect(B74DoublesCheckout.valid(remaining: 40, score: 40, darts: ['X40'], checkOut: mode), isFalse);
    }
  });
  test('unknown checkout mode fails closed', () {
    expect(() => B74DoublesCheckout.valid(remaining: 40, score: 40, darts: ['D20'], checkOut: 'anything'), throwsArgumentError);
  });
}
