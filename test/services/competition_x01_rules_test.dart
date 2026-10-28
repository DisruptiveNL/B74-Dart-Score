import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_sync_contract.dart';

void main() {
  test('default rules validate', () {
    expect(
      () => CompetitionX01Rules.validate(CompetitionX01Rules.defaults()),
      returnsNormally,
    );
  });
  test('invalid even best-of rejected', () {
    final rules = CompetitionX01Rules.defaults()..['bestOf'] = 4;
    expect(() => CompetitionX01Rules.validate(rules), throwsFormatException);
  });
  test('fixed away starter alternates across party boundaries', () {
    expect(
      CompetitionX01Rules.startingTeam(CompetitionX01Rules.fixedAway, 0),
      'away',
    );
    expect(
      CompetitionX01Rules.startingTeam(CompetitionX01Rules.fixedAway, 1),
      'home',
    );
    expect(
      CompetitionX01Rules.startingTeam(CompetitionX01Rules.fixedAway, 4),
      'away',
    );
    expect(
      CompetitionX01Rules.startingTeam(CompetitionX01Rules.bull, 0),
      isNull,
    );
  });
  test('deciding leg bull only at tied match point', () {
    expect(
      CompetitionX01Rules.needsDecidingLegBull(
        homeLegs: 2,
        awayLegs: 2,
        bestOf: 5,
        enabled: true,
      ),
      isTrue,
    );
    expect(
      CompetitionX01Rules.needsDecidingLegBull(
        homeLegs: 3,
        awayLegs: 3,
        bestOf: 7,
        enabled: true,
      ),
      isTrue,
    );
    expect(
      CompetitionX01Rules.needsDecidingLegBull(
        homeLegs: 1,
        awayLegs: 2,
        bestOf: 5,
        enabled: true,
      ),
      isFalse,
    );
    expect(
      CompetitionX01Rules.needsDecidingLegBull(
        homeLegs: 2,
        awayLegs: 2,
        bestOf: 5,
        enabled: false,
      ),
      isFalse,
    );
  });
}
