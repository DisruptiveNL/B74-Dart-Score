import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_sync_contract.dart';
import 'package:dartscore_app/services/competition_dummy_identity.dart';

void main() {
  Map<String, dynamic> packet() {
    final home = CompetitionDummyIdentity.participantId('team-home');
    final away = CompetitionDummyIdentity.participantId('team-away');
    return {
      'type': CompetitionSyncContract.type,
      'version': CompetitionSyncContract.version,
      'matchId': 'match-1',
      'home': {'id': 'team-home', 'name': 'Thuis'},
      'away': {'id': 'team-away', 'name': 'Uit'},
      'startingScore': 501,
      'singles': [
        for (var i = 1; i <= 4; i++) {
          'slot': i,
          'homePlayer': {'id': i == 1 ? home : 'home-$i', 'name': i == 1 ? 'Dummy' : 'Speler $i', 'bondNumber': i == 1 ? 'DUMMY' : 'H$i'},
          'awayPlayer': {'id': i == 1 ? away : 'away-$i', 'name': i == 1 ? 'Dummy' : 'Speler $i', 'bondNumber': i == 1 ? 'DUMMY' : 'A$i'},
        }
      ],
    };
  }
  test('Dummy aan beide kanten heeft unieke teamidentiteit', () {
    expect(() => CompetitionSyncContract.validate(packet()), returnsNormally);
  });
  test('Dummy met verkeerde teamidentiteit wordt geweigerd', () {
    final value = packet();
    (value['singles'] as List).first['awayPlayer']['id'] =
        CompetitionDummyIdentity.participantId('team-home');
    expect(() => CompetitionSyncContract.validate(value), throwsFormatException);
  });
  test('Echte speler mag Dummy-identiteit niet claimen', () {
    final value = packet();
    (value['singles'] as List)[1]['homePlayer']['id'] =
        CompetitionDummyIdentity.participantId('team-home');
    expect(() => CompetitionSyncContract.validate(value), throwsFormatException);
  });
}
