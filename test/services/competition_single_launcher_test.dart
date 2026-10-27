import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/services/competition_match_catalog.dart';
import 'package:dartscore_app/services/competition_single_launcher.dart';
import 'package:dartscore_app/services/competition_sync_contract.dart';

void main() {
  CompetitionMatchSummary match(Map<String, dynamic> rules) {
    return CompetitionMatchSummary.fromPacket({
      'type': CompetitionSyncContract.type,
      'version': CompetitionSyncContract.version,
      'matchId': 'm1',
      'home': {'id': 'h', 'name': 'Home'},
      'away': {'id': 'a', 'name': 'Away'},
      'startingScore': rules['startingScore'],
      'x01Rules': rules,
      'singles': List.generate(4, (i) => {
        'slot': i + 1,
        'homePlayer': {'id': 'h$i', 'name': 'H$i'},
        'awayPlayer': {'id': 'a$i', 'name': 'A$i'},
      }),
    }, receivedAt: 1);
  }

  test('best of 5 requires 3 won legs, and X01 modes are preserved', () {
    final rules = CompetitionX01Rules.defaults()
      ..['checkIn'] = 'master'
      ..['checkOut'] = 'straight';
    final game = CompetitionSingleLauncher.game(match(rules));
    expect(game.legs, 3);
    expect(game.sets, 1);
    expect(game.gameMode, GameMode.masterIn);
    expect(game.checkoutMode, CheckoutMode.straightOut);
    expect(game.startingOrder, StartingOrder.fixed);
  });

  test('fixed away start alternates across singles', () {
    final m = match(CompetitionX01Rules.defaults());
    expect(m.singles.map((s) => CompetitionSingleLauncher.homeStarts(m, s)),
        [false, true, false, true]);
  });

  test('bull start requires manual selection', () {
    final rules = CompetitionX01Rules.defaults()..['startPolicy'] = CompetitionX01Rules.bull;
    final m = match(rules);
    expect(CompetitionSingleLauncher.homeStarts(m, m.singles.first), isNull);
  });
}
