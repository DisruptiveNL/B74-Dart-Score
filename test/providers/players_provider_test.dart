import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/models/player.dart';
import 'package:dartscore_app/providers/players_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

void main() {
  group('PlayersProvider', () {
    useInMemoryDatabase();

    late PlayersProvider provider;

    setUp(() {
      provider = PlayersProvider();
    });

    test('starts out not loaded and empty', () {
      expect(provider.loaded, isFalse);
      expect(provider.players, isEmpty);
      expect(provider.primaryPlayer, isNull);
    });

    test(
      'puts the primary player first and the rest in alphabetical order',
      () async {
        await provider.addPlayer('Zoe');
        await provider.addPlayer('Ada');
        final nik = await provider.addPlayer('Nik');
        await provider.setPrimary(nik);

        expect(provider.players.map((p) => p.name), ['Nik', 'Ada', 'Zoe']);
      },
    );

    test(
      'ignores case, so a lower case name is not exiled to the end',
      () async {
        // Ordering by code unit puts every capital ahead of every lower case
        // letter, which is how "anna" ends up behind "Zoe" in a list of names.
        await provider.addPlayer('Zoe');
        await provider.addPlayer('anna');
        await provider.addPlayer('Bob');

        expect(provider.players.map((p) => p.name), ['anna', 'Bob', 'Zoe']);
      },
    );

    test('files the umlauts under their base letter', () async {
      // By code unit these all sort behind "Zoe", far up in the code space.
      await provider.addPlayer('Zoe');
      await provider.addPlayer('Ärger');
      await provider.addPlayer('Über');
      await provider.addPlayer('Öl');

      expect(provider.players.map((p) => p.name), [
        'Ärger',
        'Öl',
        'Über',
        'Zoe',
      ]);
    });

    test('treats ß as ss', () async {
      await provider.addPlayer('Strauss');
      await provider.addPlayer('Strauß');
      await provider.addPlayer('Straub');

      expect(provider.players.map((p) => p.name), [
        'Straub',
        'Strauss',
        'Strauß',
      ]);
    });

    test('sorts the same way after reloading from the database', () async {
      await provider.addPlayer('Zoe');
      await provider.addPlayer('Ada');
      final nik = await provider.addPlayer('Nik');
      await provider.setPrimary(nik);

      final reloaded = PlayersProvider();
      await reloaded.load();

      expect(reloaded.players.map((p) => p.name), ['Nik', 'Ada', 'Zoe']);
      expect(reloaded.loaded, isTrue);
    });

    test('leaves only one player primary when the flag moves', () async {
      final first = await provider.addPlayer('Ada');
      final second = await provider.addPlayer('Zoe');
      await provider.setPrimary(first);

      await provider.setPrimary(second);

      expect(provider.players.where((p) => p.isPrimary).map((p) => p.name), [
        'Zoe',
      ]);
      expect((await DbHelper.instance.getPrimaryPlayer())?.name, 'Zoe');
    });

    test(
      'leaves only one player primary when a new one is added as primary',
      () async {
        final ada = await provider.addPlayer('Ada');
        await provider.setPrimary(ada);

        final zoe = await provider.addPlayer('Zoe', isPrimary: true);

        expect(provider.players.where((p) => p.isPrimary).map((p) => p.id), [
          zoe.id,
        ]);
        expect((await DbHelper.instance.getPrimaryPlayer())?.id, zoe.id);
        expect(provider.primaryPlayer?.id, zoe.id);
      },
    );

    test(
      'keeps a deleted player out of the list without losing the row',
      () async {
        final ada = await provider.addPlayer('Ada');
        await provider.addPlayer('Zoe');

        await provider.deletePlayer(ada.id!);

        expect(provider.players.map((p) => p.name), ['Zoe']);
        // Soft delete: the row survives so the games that reference it still
        // resolve, it is only kept out of every list.
        expect(await DbHelper.instance.getPlayer(ada.id!), isNotNull);
      },
    );

    test('notifies on every change so the screens follow along', () async {
      var notifications = 0;
      provider.addListener(() => notifications++);

      final ada = await provider.addPlayer('Ada');
      await provider.setPrimary(ada);
      await provider.updatePlayer(ada.copyWith(name: 'Ada B'));
      await provider.deletePlayer(ada.id!);

      expect(notifications, 4);
    });

    test('renames a player in the list and in the database', () async {
      final ada = await provider.addPlayer('Ada');

      await provider.updatePlayer(ada.copyWith(name: 'Ada B'));

      expect(provider.players.single.name, 'Ada B');
      expect((await DbHelper.instance.getPlayer(ada.id!))?.name, 'Ada B');
    });

    test('looks a player up by id, and says so when there is none', () async {
      final ada = await provider.addPlayer('Ada');

      expect(provider.getById(ada.id!)?.name, 'Ada');
      expect(provider.getById(9999), isNull);
    });

    test('keeps the bots out of the roster and finds them by id', () async {
      await provider.addPlayer('Ada');
      final bot = await provider.botFor(BotLevel.pro);

      expect(provider.players.map((p) => p.name), ['Ada']);
      expect(provider.bots.single.id, bot.id);
      expect(provider.getById(bot.id!)?.botLevel, BotLevel.pro);
    });

    test('makes one row per tier and hands the same one out again', () async {
      final first = await provider.botFor(BotLevel.amateur);
      final second = await provider.botFor(BotLevel.amateur);
      await provider.botFor(BotLevel.rookie);

      expect(second.id, first.id);
      expect(provider.bots.map((b) => b.botLevel), [
        BotLevel.rookie,
        BotLevel.amateur,
      ], reason: 'weakest tier first, whatever order they were made in');
      expect((await DbHelper.instance.getBots()).length, 2);
      expect((await DbHelper.instance.getPlayers()), isEmpty);
    });

    test(
      'numbers a second bot of the same tier and keeps them apart',
      () async {
        final first = await provider.botFor(BotLevel.pro);
        final second = await provider.botFor(BotLevel.pro, ordinal: 2);
        final again = await provider.botFor(BotLevel.pro, ordinal: 2);

        expect(second.id, isNot(first.id));
        expect(again.id, second.id);
        expect(second.botOrdinal, 2);
        expect(second.uuid, BotLevel.pro.uuidFor(2));
        expect(provider.bots.map((b) => b.botOrdinal), [1, 2]);
      },
    );

    test('finds the bots it made again after a reload', () async {
      final bot = await provider.botFor(BotLevel.legend);

      final reloaded = PlayersProvider();
      await reloaded.load();

      expect(reloaded.bots.single.id, bot.id);
      expect(reloaded.bots.single.uuid, BotLevel.legend.uuid);
      expect(reloaded.players, isEmpty);
    });
  });
}
