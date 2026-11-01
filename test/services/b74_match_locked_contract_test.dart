import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/b74_match_locked_contract.dart';

void main() {
  final locked = <String, dynamic>{
    'type': B74MatchLockedContract.type,
    'version': 1,
    'matchId': 'match-123',
    'closedAt': 1793545200000,
    'homeWins': 7,
    'awayWins': 2,
  };

  test('LOCKED contract roundtrip and stable delivery identity', () {
    final decoded = B74MatchLockedContract.decode(
      B74MatchLockedContract.encode(locked),
    );
    expect(decoded, locked);
    expect(B74MatchLockedContract.deliveryId(decoded), 'match-locked:match-123');
  });

  test('reject incomplete match and invalid identity', () {
    expect(() => B74MatchLockedContract.encode({...locked, 'awayWins': 1}),
        throwsFormatException);
    expect(() => B74MatchLockedContract.encode({...locked, 'matchId': ''}),
        throwsFormatException);
  });

  test('reject invalid closure timestamp and protocol', () {
    expect(() => B74MatchLockedContract.encode({...locked, 'closedAt': 0}),
        throwsFormatException);
    expect(() => B74MatchLockedContract.encode({...locked, 'version': 2}),
        throwsFormatException);
  });
}
