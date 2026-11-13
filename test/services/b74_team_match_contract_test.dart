import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_team_match_contract.dart';

Map<String, dynamic> fixture() => {
  'type': B74TeamMatchContract.type,
  'version': 1,
  'matchId': 'match-1',
  'gameId': 'match-1-doubles-1',
  'revision': 1,
  'kind': 'doubles701',
  'slot': 1,
  'startingScore': 701,
  'bestOf': 5,
  'startPolicy': 'away',
  'home': {
    'teamId': 'home', 'teamName': 'Thuis',
    'players': [
      {'playerId': 'h1', 'name': 'H1', 'bondNumber': '101', 'position': 1},
      {'playerId': 'h2', 'name': 'H2', 'bondNumber': '102', 'position': 2},
    ],
  },
  'away': {
    'teamId': 'away', 'teamName': 'Uit',
    'players': [
      {'playerId': 'a1', 'name': 'A1', 'bondNumber': '201', 'position': 1},
      {'playerId': 'a2', 'name': 'A2', 'bondNumber': '202', 'position': 2},
    ],
  },
};

void main() {
  test('701 bericht kan heen en terug', () {
    final packet = fixture();
    expect(B74TeamMatchContract.decode(B74TeamMatchContract.encode(packet)), packet);
  });
  test('spelerstartvolgorde is verplicht', () {
    final packet = fixture();
    (packet['home']['players'][0] as Map<String, dynamic>)['position'] = 2;
    expect(() => B74TeamMatchContract.validate(packet), throwsFormatException);
  });
  test('ontbrekend bondsnummer wordt geweigerd', () {
    final packet = fixture();
    (packet['away']['players'][1] as Map<String, dynamic>).remove('bondNumber');
    expect(() => B74TeamMatchContract.validate(packet), throwsFormatException);
  });
  test('revisie nul wordt geweigerd', () {
    final packet = fixture()..['revision'] = 0;
    expect(() => B74TeamMatchContract.validate(packet), throwsFormatException);
  });
  test('biergame 1001 met vier spelers per kant', () {
    final packet = fixture();
    packet['kind'] = 'beer1001';
    packet['startingScore'] = 1001;
    packet['bestOf'] = 1;
    for (final side in ['home', 'away']) {
      final team = packet[side] as Map<String, dynamic>;
      final players = team['players'] as List;
      final prefix = side == 'home' ? 'h' : 'a';
      final start = side == 'home' ? 100 : 200;
      players.add(<String, Object>{
        'playerId': '${prefix}3', 'name': 'P3',
        'bondNumber': '${start + 3}', 'position': 3,
      });
      players.add(<String, Object>{
        'playerId': '${prefix}4', 'name': 'P4',
        'bondNumber': '${start + 4}', 'position': 4,
      });
    }
    expect(() => B74TeamMatchContract.validate(packet), returnsNormally);
  });
  test('bestaand singles type wordt niet geaccepteerd', () {
    final packet = fixture()..['type'] = 'b74.competition.match.v1';
    expect(() => B74TeamMatchContract.validate(packet), throwsFormatException);
  });
  test('DUMMY mag aan beide kanten voorkomen', () {
    final packet = fixture();
    (packet['home']['players'][0] as Map<String, dynamic>)['bondNumber'] = 'dummy';
    (packet['home']['players'][0] as Map<String, dynamic>)['playerId'] = 'b74:dummy:team:home';
    (packet['away']['players'][0] as Map<String, dynamic>)['bondNumber'] = 'DUMMY';
    (packet['away']['players'][0] as Map<String, dynamic>)['playerId'] = 'b74:dummy:team:away';
    expect(() => B74TeamMatchContract.validate(packet), returnsNormally);
  });
  test('DUMMY met gewone speler-ID wordt geweigerd', () {
    final packet = fixture();
    (packet['home']['players'][0] as Map<String, dynamic>)['bondNumber'] = 'DUMMY';
    expect(() => B74TeamMatchContract.validate(packet), throwsFormatException);
  });
  test('teamgebonden Dummy-ID bij echte speler wordt geweigerd', () {
    final packet = fixture();
    (packet['home']['players'][0] as Map<String, dynamic>)['playerId'] = 'b74:dummy:team:home';
    expect(() => B74TeamMatchContract.validate(packet), throwsFormatException);
  });
  test('echte speler mag niet aan beide kanten voorkomen', () {
    final packet = fixture();
    (packet['away']['players'][0] as Map<String, dynamic>)['bondNumber'] = '101';
    expect(() => B74TeamMatchContract.validate(packet), throwsFormatException);
  });
  test('DUMMY mag niet tweemaal binnen hetzelfde team voorkomen', () {
    final packet = fixture();
    (packet['home']['players'][0] as Map<String, dynamic>)['bondNumber'] = 'DUMMY';
    (packet['home']['players'][1] as Map<String, dynamic>)['bondNumber'] = 'dummy';
    expect(() => B74TeamMatchContract.validate(packet), throwsFormatException);
  });

}
