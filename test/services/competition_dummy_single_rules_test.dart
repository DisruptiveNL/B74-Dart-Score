import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_dummy_single_rules.dart';

void main() {
  test('DUMMY bondsnummer is hoofdletterongevoelig', () {
    expect(CompetitionDummySingleRules.isDummy(' dummy '), isTrue);
    expect(CompetitionDummySingleRules.isDummy('D9999'), isFalse);
  });
  test('een Dummy verliest direct', () {
    expect(CompetitionDummySingleRules.decide(homeBond: 'DUMMY', awayBond: '123'),
        DummySingleDecision.awayWins);
    expect(CompetitionDummySingleRules.decide(homeBond: '123', awayBond: 'dummy'),
        DummySingleDecision.homeWins);
  });
  test('twee Dummies vereisen bullwinnaar', () {
    final decision = CompetitionDummySingleRules.decide(
        homeBond: 'DUMMY', awayBond: 'dummy');
    expect(decision, DummySingleDecision.bullRequired);
    expect(() => CompetitionDummySingleRules.regulatoryLegs(
        bestOf: 5, decision: decision), throwsStateError);
    expect(CompetitionDummySingleRules.regulatoryLegs(
        bestOf: 5, decision: decision, homeWonBull: true).homeLegs, 3);
  });
  test('reglementaire uitslag volgt Bo3/5/7/9/11', () {
    for (final bestOf in [3, 5, 7, 9, 11]) {
      final legs = CompetitionDummySingleRules.regulatoryLegs(
          bestOf: bestOf, decision: DummySingleDecision.awayWins);
      expect(legs.homeLegs, 0);
      expect(legs.awayLegs, (bestOf + 1) ~/ 2);
    }
  });
}
