import 'dart:math';

import 'package:dartscore_app/utils/dartboard_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the board the bot throws at', () {
    test('finds every field and ring again at the point it is aimed at', () {
      for (final field in dartboardSegmentOrder) {
        for (final multiplier in [1, 2, 3]) {
          final target = (field: field, multiplier: multiplier);
          expect(hitAt(aimPointFor(target)), target, reason: '$target');
        }
      }
      expect(hitAt(aimPointFor((field: 25, multiplier: 2))), (
        field: 25,
        multiplier: 2,
      ));
      expect(hitAt(aimPointFor((field: 25, multiplier: 1))), (
        field: 25,
        multiplier: 1,
      ));
    });

    test('puts the 20 at the top and reads clockwise from there', () {
      expect(hitAt((x: 0, y: 130)), (field: 20, multiplier: 1));
      expect(hitAt((x: 130, y: 0)), (field: 6, multiplier: 1));
      expect(hitAt((x: 0, y: -130)), (field: 3, multiplier: 1));
      expect(hitAt((x: -130, y: 0)), (field: 11, multiplier: 1));
    });

    test('divides the neighbours of the 20 on the sector lines', () {
      // Nine degrees either side of straight up is where the 1 and the 5 begin.
      final r = BoardMm.outerSingleMiddle;
      final justInside = pi / 2 - 8.9 * pi / 180;
      final justOutside = pi / 2 - 9.1 * pi / 180;
      expect(hitAt((x: r * cos(justInside), y: r * sin(justInside))).field, 20);
      expect(
        hitAt((x: r * cos(justOutside), y: r * sin(justOutside))).field,
        1,
      );
      final leftIn = pi / 2 + 8.9 * pi / 180;
      final leftOut = pi / 2 + 9.1 * pi / 180;
      expect(hitAt((x: r * cos(leftIn), y: r * sin(leftIn))).field, 20);
      expect(hitAt((x: r * cos(leftOut), y: r * sin(leftOut))).field, 5);
    });

    test('walks the rings outwards along the 20', () {
      BoardHit at(double y) => hitAt((x: 0, y: y));

      expect(at(0), (field: 25, multiplier: 2));
      expect(at(6.3), (field: 25, multiplier: 2));
      expect(at(6.4), (field: 25, multiplier: 1));
      expect(at(15.8), (field: 25, multiplier: 1));
      expect(at(16), (field: 20, multiplier: 1));
      expect(at(98.9), (field: 20, multiplier: 1));
      expect(at(99), (field: 20, multiplier: 3));
      expect(at(106.9), (field: 20, multiplier: 3));
      expect(at(107), (field: 20, multiplier: 1));
      expect(at(161.9), (field: 20, multiplier: 1));
      expect(at(162), (field: 20, multiplier: 2));
      expect(at(170), (field: 20, multiplier: 2));
      expect(at(170.1), boardMiss);
    });

    test('scores a hit the way X01 counts it', () {
      expect(scoreOf((field: 20, multiplier: 3)), 60);
      expect(scoreOf((field: 16, multiplier: 2)), 32);
      expect(scoreOf((field: 25, multiplier: 1)), 25);
      expect(scoreOf((field: 25, multiplier: 2)), 50);
      expect(scoreOf(boardMiss), 0);
    });
  });
}
