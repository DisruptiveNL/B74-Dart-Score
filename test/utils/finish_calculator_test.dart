import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/utils/finish_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FinishCalculator.getRoutes - favorite double alternative', () {
    test('alternative leads to the favorite double when primary does not', () {
      final routes = FinishCalculator.getRoutes(100, 'D16');

      expect(routes.primary, ['T20', 'D20']);
      expect(routes.alternative, ['T20', 'S8', 'D16']);
    });

    test('keeps the existing alternative when primary already finishes on '
        'the favorite double', () {
      final routes = FinishCalculator.getRoutes(125, 'D20');

      expect(routes.primary, ['25', 'T20', 'D20']);
      expect(routes.alternative, ['T20', 'T15', 'D10']);
    });

    test('offers a favorite-double route as a hint when no checkout fits '
        'the remaining darts this turn', () {
      final routes = FinishCalculator.getRoutes(55, 'D8', maxDarts: 1);

      expect(routes.primary, isNull);
      expect(routes.alternative, ['T13', 'D8']);
    });

    test('returns no alternative when no favorite-double route exists '
        'within 3 darts', () {
      final routes = FinishCalculator.getRoutes(
        170,
        'D8',
        maxDarts: 1,
        checkoutMode: CheckoutMode.doubleOut,
      );

      expect(routes.primary, isNull);
      expect(routes.alternative, isNull);
    });
  });

  group('FinishCalculator.canFinishWithOneDart', () {
    bool can(int remaining, CheckoutMode mode) =>
        FinishCalculator.canFinishWithOneDart(remaining, mode);

    test('double-out finishes on a double or the bull only', () {
      const mode = CheckoutMode.doubleOut;

      expect(can(2, mode), isTrue);
      expect(can(16, mode), isTrue);
      expect(can(40, mode), isTrue);
      expect(can(50, mode), isTrue);

      expect(can(1, mode), isFalse, reason: 'no dart scores 1 on a double');
      expect(can(15, mode), isFalse, reason: 'odd');
      expect(can(25, mode), isFalse, reason: 'the outer bull is a single');
      expect(can(41, mode), isFalse);
      expect(can(42, mode), isFalse, reason: 'even but above D20');
      expect(can(60, mode), isFalse, reason: 'T20 is not a double');
    });

    test('master-out adds the triples and the outer bull', () {
      const mode = CheckoutMode.masterOut;

      expect(can(3, mode), isTrue);
      expect(can(40, mode), isTrue);
      expect(can(42, mode), isTrue, reason: 'T14');
      expect(can(60, mode), isTrue, reason: 'T20');
      expect(
        can(25, mode),
        isTrue,
        reason: 'the outer bull counts as a single',
      );
      expect(can(50, mode), isTrue);

      expect(can(1, mode), isFalse);
      expect(can(41, mode), isFalse);
      expect(can(61, mode), isFalse);
    });

    test('straight-out finishes on any single dart that hits the number', () {
      const mode = CheckoutMode.straightOut;

      expect(can(1, mode), isTrue, reason: 'S1');
      expect(can(20, mode), isTrue);
      expect(can(22, mode), isTrue, reason: 'D11');
      expect(can(25, mode), isTrue);
      expect(can(42, mode), isTrue, reason: 'T14');
      expect(can(50, mode), isTrue);
      expect(can(60, mode), isTrue);

      expect(can(23, mode), isFalse, reason: 'no single dart scores 23');
      expect(can(41, mode), isFalse);
      expect(can(61, mode), isFalse);
    });

    test('a remaining of zero or less is never one dart away', () {
      for (final mode in CheckoutMode.values) {
        expect(can(0, mode), isFalse);
        expect(can(-3, mode), isFalse);
      }
    });
  });

  group('every suggested route', () {
    /// Points and finishing rule of one dart in route notation: `Bull` is the
    /// bull's eye (50, a double), `25` the outer bull, `S`, `D` and `T` the
    /// rings of 1 to 20. Null for anything else, which no route may hold.
    ({int score, int field, int multiplier})? dart(String label) {
      if (label == 'Bull') return (score: 50, field: 25, multiplier: 2);
      if (label == '25') return (score: 25, field: 25, multiplier: 1);
      final m = RegExp(r'^([SDT])(\d+)$').firstMatch(label);
      if (m == null) return null;
      final field = int.parse(m.group(2)!);
      if (field < 1 || field > 20) return null;
      final multiplier = {'S': 1, 'D': 2, 'T': 3}[m.group(1)]!;
      return (score: field * multiplier, field: field, multiplier: multiplier);
    }

    test('adds up to the rest and finishes under the check-out rule', () {
      final wrong = <String>[];
      for (final mode in CheckoutMode.values) {
        for (var rest = 2; rest <= 170; rest++) {
          for (final favourite in const [null, 'D16', 'D20', 'D1', 'Bull']) {
            final routes = FinishCalculator.getRoutes(
              rest,
              favourite,
              checkoutMode: mode,
            );
            for (final route in [routes.primary, routes.alternative]) {
              if (route == null) continue;
              final darts = route.map(dart).toList();
              if (darts.contains(null)) {
                wrong.add('${mode.name} $rest $route: not a dart');
                continue;
              }
              final sum = darts.fold(0, (a, d) => a + d!.score);
              final last = darts.last!;
              if (sum != rest) {
                wrong.add('${mode.name} $rest $route: adds up to $sum');
              } else if (!FinishCalculator.finishesOn(
                last.field,
                last.multiplier,
                mode,
              )) {
                wrong.add('${mode.name} $rest $route: no legal finish');
              }
            }
          }
        }
      }

      expect(wrong.toSet(), isEmpty);
    });
  });
}
