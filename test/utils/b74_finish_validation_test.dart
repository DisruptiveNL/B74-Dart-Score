import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/utils/b74_finish_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B74 finishdart validatie', () {
    test('double-out met een dart: dubbel of bull', () {
      expect(b74CanFinishInDarts(40, 1, CheckoutMode.doubleOut), isTrue);
      expect(b74CanFinishInDarts(50, 1, CheckoutMode.doubleOut), isTrue);
      expect(b74CanFinishInDarts(25, 1, CheckoutMode.doubleOut), isFalse);
      expect(b74CanFinishInDarts(100, 1, CheckoutMode.doubleOut), isFalse);
    });
    test('double-out met twee darts', () {
      expect(b74CanFinishInDarts(110, 2, CheckoutMode.doubleOut), isTrue);
      expect(b74CanFinishInDarts(111, 2, CheckoutMode.doubleOut), isFalse);
      expect(b74CanFinishInDarts(170, 2, CheckoutMode.doubleOut), isFalse);
    });
    test('170 vereist drie darts en bogeys zijn onmogelijk', () {
      expect(b74CanFinishInDarts(170, 3, CheckoutMode.doubleOut), isTrue);
      for (final bogey in [159, 162, 163, 165, 166, 168, 169]) {
        expect(b74CanFinishInDarts(bogey, 3, CheckoutMode.doubleOut), isFalse);
      }
    });
    test('straight-out en master-out hebben andere finishvelden', () {
      expect(b74CanFinishInDarts(25, 1, CheckoutMode.straightOut), isTrue);
      expect(b74CanFinishInDarts(60, 1, CheckoutMode.masterOut), isTrue);
      expect(b74CanFinishInDarts(60, 1, CheckoutMode.doubleOut), isFalse);
    });
    test('ongeldige darttellingen en restscore worden geweigerd', () {
      expect(b74CanFinishInDarts(40, 0, CheckoutMode.doubleOut), isFalse);
      expect(b74CanFinishInDarts(40, 4, CheckoutMode.doubleOut), isFalse);
      expect(b74CanFinishInDarts(0, 1, CheckoutMode.doubleOut), isFalse);
    });
  });
}
