import 'package:dartscore_app/l10n/app_localizations.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/utils/player_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scoreboard slot with only what naming it needs.
class _Slot implements LabelledSlot {
  @override
  final String displayName;
  @override
  final List<Player> players;
  @override
  final bool isTeamSlot;

  _Slot(this.displayName, this.players, {this.isTeamSlot = false});
}

void main() {
  const en = AppLocalizations(Locale('en'));
  const de = AppLocalizations(Locale('de'));

  group('the name a player is shown under', () {
    test('is the stored name for a person in every language', () {
      final ada = Player(name: 'Ada');

      expect(ada.label(en), 'Ada');
      expect(ada.label(de), 'Ada');
    });

    test('is the localized tier name for a bot, not the stored one', () {
      final bot = Player(name: BotLevel.pro.storedName, botLevel: BotLevel.pro);

      expect(bot.label(en), 'Pro bot');
      expect(bot.label(de), 'Profi-Bot');
      expect(bot.name, 'Bot Pro');
    });

    test('numbers a bot from the second of its tier on', () {
      final second = Player(
        name: 'Bot Pro 2',
        botLevel: BotLevel.pro,
        botOrdinal: 2,
      );

      expect(second.label(en), 'Pro bot 2');
      expect(second.label(de), 'Profi-Bot 2');
      expect(
        Player(
          name: 'Bot Pro',
          botLevel: BotLevel.pro,
          botOrdinal: 1,
        ).label(en),
        'Pro bot',
      );
    });

    test('keeps every German bot name one word for the compact scoreboard', () {
      for (final level in BotLevel.values) {
        final bot = Player(name: level.storedName, botLevel: level);
        expect(
          bot.label(de).split(' ').first,
          bot.label(de),
          reason: '${level.name} splits into two words',
        );
      }
    });

    test('names a slot by its team, or by the one player in it', () {
      final bot = Player(name: 'Bot Legend', botLevel: BotLevel.legend);

      expect(
        _Slot('Us', [Player(name: 'Ada'), bot], isTeamSlot: true).label(en),
        'Us',
      );
      expect(_Slot(bot.name, [bot]).label(en), 'Legend bot');
    });

    test('joins several players with the given separator', () {
      final players = [
        Player(name: 'Ada'),
        Player(name: 'Bot Rookie', botLevel: BotLevel.rookie),
      ];

      expect(players.labels(de, ' & '), 'Ada & Anfänger-Bot');
    });
  });
}
