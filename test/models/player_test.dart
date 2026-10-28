import 'package:dartscore_app/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a computer opponent as a player', () {
    test('round-trips its tier through the row map', () {
      final bot = Player(
        name: BotLevel.semiPro.storedName,
        uuid: BotLevel.semiPro.uuid,
        botLevel: BotLevel.semiPro,
      );

      final back = Player.fromMap(bot.toMap());

      expect(back.isBot, isTrue);
      expect(back.botLevel, BotLevel.semiPro);
      expect(back.name, 'Bot Semi-Pro');
      expect(back.uuid, BotLevel.semiPro.uuid);
    });

    test('is a person when the column is null or missing', () {
      final human = Player(name: 'Ada');

      expect(human.isBot, isFalse);
      expect(human.toMap()['bot_level'], isNull);
      expect(Player.fromMap({'name': 'Ada'}).botLevel, isNull);
    });

    test('keeps its tier and number through copyWith', () {
      final bot = Player(
        name: 'Bot Pro 2',
        botLevel: BotLevel.pro,
        botOrdinal: 2,
      );

      expect(bot.copyWith(id: 7).botLevel, BotLevel.pro);
      expect(bot.copyWith(id: 7).botOrdinal, 2);
      expect(bot.copyWith(favoriteDoubles: 'D16').isBot, isTrue);
    });

    test('is the first of its tier when the row predates the numbering', () {
      final back = Player.fromMap({'name': 'Bot Pro', 'bot_level': 3});

      expect(back.botOrdinal, 1);
      expect(Player.fromMap({'name': 'Ada'}).botOrdinal, isNull);
    });

    test('round-trips its number', () {
      final bot = Player(
        name: BotLevel.legend.storedNameFor(3),
        uuid: BotLevel.legend.uuidFor(3),
        botLevel: BotLevel.legend,
        botOrdinal: 3,
      );

      final back = Player.fromMap(bot.toMap());

      expect(back.botOrdinal, 3);
      expect(back.name, 'Bot Legend 3');
    });
  });

  group('the bot tiers', () {
    test(
      'store their index, weakest first, so the order is part of the schema',
      () {
        expect(BotLevel.values.first, BotLevel.rookie);
        expect(BotLevel.values.last, BotLevel.legend);
        expect(BotLevel.pro.index, 3);
      },
    );

    test('each have a uuid of their own that no generator produces', () {
      final uuids = BotLevel.values.map((l) => l.uuid).toSet();

      expect(uuids.length, BotLevel.values.length);
      for (final u in uuids) {
        expect(u, matches(RegExp(r'^0{8}-0{4}-4000-8000-0{9}b\d{2}$')));
      }
      // Numbered bots get uuids of their own in the same range, and the
      // first keeps the one it had before there was a number.
      expect(BotLevel.pro.uuidFor(1), BotLevel.pro.uuid);
      expect(BotLevel.pro.uuidFor(2), '00000000-0000-4000-8000-000000001b03');
      expect(BotLevel.pro.storedNameFor(1), 'Bot Pro');
      expect(BotLevel.pro.storedNameFor(2), 'Bot Pro 2');
      // A generated uuid never starts with eight zeros, or the tiers could
      // collide with a person made on some other device.
      expect(Player(name: 'x').uuid, isNot(startsWith('00000000-')));
    });
  });
}
