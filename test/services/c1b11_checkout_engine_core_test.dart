import 'package:dartscore_app/services/b74_doubles_701.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  B74Doubles701 create(String mode) {
    final engine = B74Doubles701(starterTeam: 0, checkOut: mode);
    engine.confirmLegStarter(0);
    return engine;
  }

  test('existing double out default still rejects remaining one', () {
    final engine = create('double');
    expect(engine.checkOut, 'double');
    for (final score in [180, 180, 180]) {
      engine.completeVisit(score: score);
      engine.completeVisit(score: 0);
    }
    expect(() => engine.completeVisit(score: 160), throwsStateError);
    expect(engine.remaining[0], 161);
  });

  test('master out still rejects remaining one', () {
    final engine = create('master');
    for (final score in [180, 180, 180]) {
      engine.completeVisit(score: score);
      engine.completeVisit(score: 0);
    }
    expect(() => engine.completeVisit(score: 160), throwsStateError);
    expect(engine.remaining[0], 161);
  });

  test('straight out allows remaining one without checkout', () {
    final engine = create('straight');
    // Reach a realistic score through legal visits (max 180 per visit).
    for (final score in [180, 180, 180, 160]) {
      engine.completeVisit(score: score);
      engine.completeVisit(score: 0);
    }
    expect(engine.remaining[0], 1);
    expect(engine.winner, isNull);
    engine.completeVisit(score: 1, validCheckout: true);
    expect(engine.legsWon[0], 1);
  });

  test('straight out still rejects negative remaining', () {
    final engine = create('straight');
    expect(
      () => engine.completeVisit(score: 180, validCheckout: true),
      throwsStateError,
    );
    expect(engine.remaining[0], 701);
  });

  test('unsupported checkout mode fails closed', () {
    expect(
      () => B74Doubles701(starterTeam: 0, checkOut: 'other'),
      throwsArgumentError,
    );
  });
}
