import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_sync_contract.dart';

void main() {
  Map<String, dynamic> player(String id) => {
    'id': id,
    'name': 'Player $id',
    'bondNumber': 'B$id',
  };

  Map<String, dynamic> packet() => {
    'type': CompetitionSyncContract.type,
    'version': CompetitionSyncContract.version,
    'matchId': 'match-1',
    'home': {'id': 'home', 'name': 'Home'},
    'away': {'id': 'away', 'name': 'Away'},
    'startingScore': 501,
    'singles': [
      for (var slot = 1; slot <= 4; slot++)
        {
          'slot': slot,
          'homePlayer': player('h$slot'),
          'awayPlayer': player('a$slot'),
        },
    ],
  };

  test('valid competition match roundtrips', () {
    final source = packet();
    expect(
      CompetitionSyncContract.decode(CompetitionSyncContract.encode(source)),
      source,
    );
  });

  test('rejects repeated player', () {
    final source = packet();
    (source['singles'] as List)[1]['homePlayer'] = player('h1');
    expect(() => CompetitionSyncContract.encode(source), throwsFormatException);
  });

  test('rejects duplicate slot', () {
    final source = packet();
    (source['singles'] as List)[1]['slot'] = 1;
    expect(() => CompetitionSyncContract.encode(source), throwsFormatException);
  });

  test('rejects unsupported version', () {
    final source = packet()..['version'] = 2;
    expect(() => CompetitionSyncContract.encode(source), throwsFormatException);
  });
}
