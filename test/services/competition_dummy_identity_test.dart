import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_dummy_identity.dart';

void main() {
  test('DUMMY is case insensitive and not D9999', () {
    expect(CompetitionDummyIdentity.isDummyBond(' dummy '), isTrue);
    expect(CompetitionDummyIdentity.isDummyBond('D9999'), isFalse);
  });
  test('different team IDs give different stable participant IDs', () {
    final home = CompetitionDummyIdentity.participantId('team-home');
    final away = CompetitionDummyIdentity.participantId('team-away');
    expect(home, isNot(away));
    expect(home, CompetitionDummyIdentity.participantId('team-home'));
    expect(CompetitionDummyIdentity.isParticipantId(home), isTrue);
    expect(CompetitionDummyIdentity.isParticipantId('real-player'), isFalse);
  });
  test('team name not needed; invalid team ID rejected', () {
    expect(() => CompetitionDummyIdentity.participantId(' '), throwsArgumentError);
    expect(CompetitionDummyIdentity.participantId('team/a'),
        'b74:dummy:team:team%2Fa');
  });
}
