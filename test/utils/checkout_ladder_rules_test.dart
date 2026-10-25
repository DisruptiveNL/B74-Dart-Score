import 'package:dartscore_app/models/checkout_ladder_game.dart';
import 'package:dartscore_app/utils/checkout_ladder_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// A game with the given settings and nothing else that matters to the rules.
CheckoutLadderGame _game({
  CheckoutLadderVariant variant = CheckoutLadderVariant.training,
  int start = 81,
  int? target,
  int darts = 6,
  int? stepFrom,
  int? stepDarts,
  CheckoutMode checkOut = CheckoutMode.doubleOut,
}) =>
    CheckoutLadderGame(
      variant:         variant,
      startNumber:     start,
      targetNumber:    target,
      dartsPerAttempt: darts,
      stepFrom:        stepFrom,
      stepDarts:       stepDarts,
      checkOut:        checkOut,
      createdAt:       DateTime(2026, 10, 25),
      playerIds:       const [1, 2],
    );

/// Reads one dart in the board's notation: `T20`, `D16`, `S5`, `25`, `B` for
/// the bull and `M` for a miss.
LadderDart _dart(String s) {
  if (s == 'M') return (field: 0, multiplier: 0);
  if (s == 'B') return (field: 25, multiplier: 2);
  if (s == '25') return (field: 25, multiplier: 1);
  final m = switch (s[0]) { 'T' => 3, 'D' => 2, _ => 1 };
  return (field: int.parse(s.substring(1)), multiplier: m);
}

/// Throws [darts] (space separated) into [engine], closing every visit the
/// moment it ends, the way the replay does.
void _play(CheckoutLadderEngine engine, String darts) {
  for (final s in darts.split(' ').where((s) => s.isNotEmpty)) {
    final d = _dart(s);
    expect(engine.throwDart(d.field, d.multiplier), isNotNull,
        reason: 'dart $s was refused');
    if (engine.visitOver) engine.endVisit();
  }
}

/// [count] misses in a row.
String _misses(int count) => List.filled(count, 'M').join(' ');

void main() {
  group('applyLadderDart', () {
    final game = _game();

    test('a scoring dart lowers the rest and keeps the visit open', () {
      final step = applyLadderDart(
        game:       game,
        position:   LadderPosition.start(81),
        field:      20,
        multiplier: 3,
      );

      expect(step.position.rest, 21);
      expect(step.visitOver, isFalse);
      expect(step.checked, isFalse);
    });

    test('a bust goes back to the start of the visit and uses it up', () {
      var p = LadderPosition.start(81);
      for (final d in [(20, 1), (20, 1)]) {
        p = applyLadderDart(game: game, position: p, field: d.$1, multiplier: d.$2).position;
      }
      final step = applyLadderDart(game: game, position: p, field: 20, multiplier: 3);

      expect(step.bust, isTrue);
      expect(step.visitOver, isTrue);
      expect(step.attemptOver, isFalse);
      expect(step.position.rest, 81);
      expect(step.position.dartsInAttempt, 3);
    });

    test('a bust on the first dart still costs the whole visit', () {
      final step = applyLadderDart(
          game: game, position: LadderPosition.start(40), field: 20, multiplier: 3);

      expect(step.bust, isTrue);
      expect(step.position.dartsInAttempt, 3);
    });

    test('leaving one is a bust under double out', () {
      var p = LadderPosition.start(81);
      p = applyLadderDart(game: game, position: p, field: 20, multiplier: 3).position;
      final step = applyLadderDart(game: game, position: p, field: 20, multiplier: 1);

      expect(step.bust, isTrue);
      expect(step.position.rest, 81);
    });

    test('a single on the last points is a bust under double out', () {
      final step = applyLadderDart(
          game: game, position: LadderPosition.start(20), field: 20, multiplier: 1);

      expect(step.bust, isTrue);
    });

    test('master out finishes on a triple, straight out on a single', () {
      final master = applyLadderDart(
        game:       _game(checkOut: CheckoutMode.masterOut),
        position:   LadderPosition.start(60),
        field:      20,
        multiplier: 3,
      );
      final straight = applyLadderDart(
        game:       _game(checkOut: CheckoutMode.straightOut),
        position:   LadderPosition.start(20),
        field:      20,
        multiplier: 1,
      );

      expect(master.checked, isTrue);
      expect(straight.checked, isTrue);
    });

    test('checking 170 completes the ladder', () {
      var p = LadderPosition.start(170);
      p = applyLadderDart(game: game, position: p, field: 20, multiplier: 3).position;
      p = applyLadderDart(game: game, position: p, field: 20, multiplier: 3).position;
      final step = applyLadderDart(game: game, position: p, field: 25, multiplier: 2);

      expect(step.checked, isTrue);
      expect(step.position.completed, isTrue);
      expect(step.position.number, 170);
    });
  });

  group('one ladder', () {
    test('plays the example from the plan', () {
      final engine = CheckoutLadderEngine(_game(), const [1]);
      LadderPosition at() => engine.slots.single.position;

      // 81, first attempt: checked with dart five.
      _play(engine, 'M M M T15 D18');
      expect(at().number, 82);
      expect(at().floor, 81);
      expect(at().climbing, isTrue);

      // 82, both attempts missed: down to 81, falling.
      _play(engine, _misses(6));
      expect(at().number, 82);
      expect(at().attempt, 2);
      _play(engine, _misses(6));
      expect(at().number, 81);
      expect(at().climbing, isFalse);

      // 81 is the floor: a miss leaves the slot where it is.
      _play(engine, _misses(6));
      expect(at().number, 81);

      // 81 in three darts: a safehouse, the floor moves to 82.
      _play(engine, 'T15 S16 D10');
      expect(at().number, 82);
      expect(at().floor, 82);
      expect(engine.slots.single.safehouses, 1);

      // 82 with the sixth dart: up to 83, no safehouse.
      _play(engine, 'M M M T14 M D20');
      expect(at().number, 83);
      expect(at().floor, 82);

      // 83 missed twice: down to 82, which is now the floor.
      _play(engine, _misses(12));
      expect(at().number, 82);
      _play(engine, _misses(6));
      expect(at().number, 82);
      expect(at().onFloor, isTrue);

      final slot = engine.slots.single;
      expect(slot.checks, 3);
      expect(slot.drops, 2);
      expect(slot.highestChecked, 82);
      expect(slot.attemptsCompleted, 9);
      expect(slot.dartsPerCheck, closeTo((5 + 3 + 6) / 3, 1e-9));
      expect(slot.checkRate, closeTo(3 / 9, 1e-9));
    });

    test('a falling slot has a single attempt', () {
      final engine = CheckoutLadderEngine(_game(), const [1]);
      _play(engine, 'T15 S16 D10');          // 81, safehouse: floor 82
      _play(engine, 'T14 D20');              // 82, safehouse: floor 83
      _play(engine, 'T15 D19');              // 83, safehouse: floor 84
      _play(engine, 'M M M T14 S10 D16');    // 84 checked late, floor stays 84
      _play(engine, _misses(12));            // 85 missed twice
      expect(engine.slots.single.position.number, 84);
      expect(engine.slots.single.position.onFloor, isTrue);
    });

    test('drops a number after one failed attempt when falling', () {
      final engine = CheckoutLadderEngine(_game(), const [1]);
      _play(engine, 'M M M T15 D18');        // 81, late: 82
      _play(engine, 'M M M T14 M D20');      // 82, late: 83
      _play(engine, _misses(12));            // 83 twice: 82, falling
      _play(engine, _misses(6));             // 82 once: 81
      expect(engine.slots.single.position.number, 81);
    });

    test('a bust in the first visit leaves the second to play', () {
      final engine = CheckoutLadderEngine(_game(), const [1]);
      _play(engine, 'S20 S20 T20');          // bust, visit over
      expect(engine.slots.single.position.rest, 81);
      _play(engine, 'T15 S16 D10');          // checked in the second visit
      expect(engine.slots.single.position.number, 82);
      expect(engine.slots.single.position.floor, 81);
      expect(engine.slots.single.busts, 1);
    });

    test('the step gives an attempt more darts from its number on', () {
      final engine = CheckoutLadderEngine(
          _game(darts: 6, stepFrom: 82, stepDarts: 9), const [1]);
      _play(engine, 'M M M T15 D18');        // 81 in six darts
      _play(engine, _misses(6));
      expect(engine.slots.single.position.attempt, 1,
          reason: 'an attempt on 82 holds nine darts');
      _play(engine, 'M M M');
      expect(engine.slots.single.position.attempt, 2);
    });

    test('training ends when the ladder is completed', () {
      final engine = CheckoutLadderEngine(_game(start: 170), const [1]);
      _play(engine, 'T20 T20 B');

      expect(engine.gameOver, isTrue);
      expect(engine.slots.single.position.completed, isTrue);
    });
  });

  group('visits', () {
    test('end on a check, a bust or the third dart, each with its result', () {
      final engine = CheckoutLadderEngine(_game(), const [1]);
      _play(engine, 'S20 S20 T20');          // bust on the third dart
      _play(engine, 'T15 D18');              // 81 checked with two darts
      _play(engine, 'S20 M M');              // 82, nothing checked

      final visits = engine.slots.single.visits;
      expect(visits.map((v) => v.darts.length), [3, 2, 3]);
      expect(visits[0].bust, isTrue);
      expect(visits[0].restAfter, 81);
      expect(visits[1].checked, isTrue);
      expect(visits[1].number, 81);
      expect(visits[2].restAfter, 62);
    });

    test('keep the rest an attempt stopped on, not the next attempt\'s', () {
      final engine = CheckoutLadderEngine(_game(), const [1]);
      _play(engine, 'T15 D18');              // 81, up to 82
      _play(engine, 'S20 M M');
      _play(engine, 'S1 M M');               // attempt over on 61

      expect(engine.slots.single.visits.last.restAfter, 61);
      expect(engine.slots.single.position.rest, 82);
    });
  });

  group('turns', () {
    test('move on after every visit', () {
      final engine = CheckoutLadderEngine(_game(), const [1, 1]);
      _play(engine, 'M M M');
      expect(engine.currentSlot, 1);
      _play(engine, 'M M M');
      expect(engine.currentSlot, 0);
      expect(engine.slots[0].position.dartsInAttempt, 3);
    });

    test('a visit ends early on a check and the turn moves on', () {
      final engine = CheckoutLadderEngine(_game(), const [1, 1]);
      final first = engine.throwDart(20, 3)!;
      expect(first.visitOver, isFalse);
      engine.throwDart(7, 1);
      final last = engine.throwDart(7, 2)!;

      expect(last.checked, isTrue);
      expect(engine.visitOver, isTrue);
      expect(engine.currentVisit, hasLength(3));
      expect(engine.throwDart(20, 1), isNull,
          reason: 'nothing lands until the visit is closed');
      engine.endVisit();
      expect(engine.currentSlot, 1);
      expect(engine.currentVisit, isEmpty);
    });

    test('team members take the visits in turn, the starter moving on', () {
      final engine = CheckoutLadderEngine(_game(), const [2]);
      final slot = engine.slots.single;
      final members = <int>[];
      for (var visit = 0; visit < 6; visit++) {
        members.add(slot.currentMember);
        _play(engine, 'M M M');
      }

      // Attempt one: 0 then 1. Attempt two: 1 then 0. Attempt three: 0, 1.
      expect(members, [0, 1, 1, 0, 0, 1]);
    });

    test('a team attempt checked in its first visit hands the next one on', () {
      final engine = CheckoutLadderEngine(_game(), const [2]);
      final slot = engine.slots.single;
      expect(slot.currentMember, 0);
      _play(engine, 'T15 S16 D10');
      expect(slot.currentMember, 1);
    });
  });

  group('race', () {
    CheckoutLadderEngine race() => CheckoutLadderEngine(
        _game(variant: CheckoutLadderVariant.race, target: 82), const [1, 1]);

    test('the others still play to the same number of attempts', () {
      final engine = race();
      _play(engine, 'T15 S16 D10');          // A: 81
      _play(engine, 'M M M');                // B: 81, first visit
      _play(engine, 'T14 D20');              // A: 82 in its second attempt
      expect(engine.gameOver, isFalse);
      expect(engine.currentSlot, 1);

      _play(engine, 'M M M');                // B: first attempt over
      expect(engine.gameOver, isFalse);
      expect(engine.currentSlot, 1, reason: 'A has nothing left to throw');

      _play(engine, _misses(6));             // B: second attempt over
      expect(engine.gameOver, isTrue,
          reason: 'B has used the two attempts A needed');
      expect(engine.winner, 0);
    });

    test('a level race on attempts goes to the fewer darts', () {
      final engine = race();
      _play(engine, 'T15 S16 D10');          // A: 81 in three
      _play(engine, 'T15 S16 D10');          // B: 81 in three
      _play(engine, 'T14 M D20');            // A: 82 in three, six in all
      _play(engine, 'T14 D20');              // B: 82 in two, five in all

      expect(engine.gameOver, isTrue);
      expect(engine.winner, 1);
    });

    test('a full tie goes to sudden death on the number above', () {
      final engine = race();
      _play(engine, 'T15 S16 D10');
      _play(engine, 'T15 S16 D10');
      _play(engine, 'T14 D20');
      _play(engine, 'T14 D20');

      expect(engine.gameOver, isFalse);
      expect(engine.suddenDeathNumber, 83);
      expect(engine.currentSlot, 0);
      expect(engine.slots[0].position.number, 83);

      _play(engine, 'T17 D16');              // A: 83 in two
      _play(engine, _misses(6));             // B: missed
      expect(engine.gameOver, isTrue);
      expect(engine.winner, 0);
    });

    test('nobody checking the sudden death replays it on the same number', () {
      final engine = race();
      _play(engine, 'T15 S16 D10');
      _play(engine, 'T15 S16 D10');
      _play(engine, 'T14 D20');
      _play(engine, 'T14 D20');
      _play(engine, _misses(6));
      _play(engine, _misses(6));

      expect(engine.gameOver, isFalse);
      expect(engine.suddenDeathNumber, 83);
      expect(engine.slots[0].position.number, 83);
      expect(engine.currentSlot, 0);
    });

    test('a target on the start number goes to the first check', () {
      final engine = CheckoutLadderEngine(
          _game(variant: CheckoutLadderVariant.race, start: 170, target: 170),
          const [1, 1]);
      _play(engine, 'T20 T20 B');            // A: 170
      _play(engine, _misses(6));             // B: one attempt, as many as A

      expect(engine.gameOver, isTrue);
      expect(engine.winner, 0);
    });

    test('a slot that checked the target throws no more', () {
      final engine = CheckoutLadderEngine(
          _game(variant: CheckoutLadderVariant.race, target: 82),
          const [1, 1, 1]);
      _play(engine, 'T15 S16 D10');          // A: 81
      _play(engine, 'M M M');                // B
      _play(engine, 'M M M');                // C
      _play(engine, 'T14 D20');              // A: target in attempt two
      _play(engine, 'M M M');                // B: attempt one over
      expect(engine.currentSlot, 2, reason: 'A is skipped from here on');
    });
  });
}
