import 'package:dartscore_app/models/game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Game handicap persistence', () {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);

    test('round-trips per-player handicaps through the row map', () {
      final game = Game(
        startScore: 501,
        createdAt: createdAt,
        handicaps: {
          7: const PlayerHandicap(
            checkIn: GameMode.doubleIn,
            checkOut: CheckoutMode.masterOut,
          ),
          9: const PlayerHandicap(checkIn: GameMode.masterIn),
        },
      );

      final restored = Game.fromMap(game.toMap());

      expect(restored.handicaps!.keys, containsAll([7, 9]));
      expect(restored.handicaps![7]!.checkIn, GameMode.doubleIn);
      expect(restored.handicaps![7]!.checkOut, CheckoutMode.masterOut);
      expect(restored.handicaps![9]!.checkIn, GameMode.masterIn);
      expect(restored.handicaps![9]!.checkOut, CheckoutMode.doubleOut);
    });

    test('stores no handicap json for a game without handicaps', () {
      final game = Game(startScore: 501, createdAt: createdAt);

      expect(game.toMap()['handicap_json'], isNull);
      expect(game.hasHandicaps, isFalse);
      expect(Game.fromMap(game.toMap()).handicaps, isNull);
    });

    test('reads rows written before the handicap column existed', () {
      final map = Game(startScore: 301, createdAt: createdAt).toMap()
        ..remove('handicap_json');

      final restored = Game.fromMap(map);

      expect(restored.handicaps, isNull);
      expect(restored.hasHandicaps, isFalse);
    });

    test('falls back to the game defaults for players without a handicap', () {
      final game = Game(
        startScore: 501,
        gameMode: GameMode.straightIn,
        checkoutMode: CheckoutMode.doubleOut,
        createdAt: createdAt,
        handicaps: {
          7: const PlayerHandicap(
            checkIn: GameMode.doubleIn,
            checkOut: CheckoutMode.masterOut,
          ),
        },
      );

      expect(game.checkInFor(7), GameMode.doubleIn);
      expect(game.checkOutFor(7), CheckoutMode.masterOut);
      expect(game.checkInFor(9), GameMode.straightIn);
      expect(game.checkOutFor(9), CheckoutMode.doubleOut);
      expect(game.checkInFor(null), GameMode.straightIn);
    });

    test('keeps teams and handicaps side by side', () {
      final game = Game(
        startScore: 501,
        createdAt: createdAt,
        teams: const [
          TeamConfig(name: 'Team 1', playerIds: [7, 8]),
          TeamConfig(name: 'Team 2', playerIds: [9]),
        ],
        handicaps: {7: const PlayerHandicap(checkOut: CheckoutMode.masterOut)},
      );

      final restored = Game.fromMap(game.toMap());

      expect(restored.isTeamGame, isTrue);
      expect(restored.hasHandicaps, isTrue);
      expect(restored.teams!.map((t) => t.name), ['Team 1', 'Team 2']);
      // The handicap applies to the one member that has it, not to the team.
      expect(restored.checkOutFor(7), CheckoutMode.masterOut);
      expect(restored.checkOutFor(8), CheckoutMode.doubleOut);
    });

    test('carries handicaps through copyWith', () {
      final game = Game(
        startScore: 501,
        createdAt: createdAt,
        handicaps: {7: const PlayerHandicap(checkIn: GameMode.doubleIn)},
      );

      final finished = game.copyWith(finishedAt: createdAt);

      expect(finished.handicaps![7]!.checkIn, GameMode.doubleIn);
    });
  });

  group('Game starting order persistence', () {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);

    test('defaults to a random order', () {
      final game = Game(startScore: 501, createdAt: createdAt);

      expect(game.startingOrder, StartingOrder.random);
      expect(game.toMap()['starting_order'], 0);
    });

    test('round-trips a fixed order through the row map', () {
      final game = Game(
        startScore: 501,
        createdAt: createdAt,
        startingOrder: StartingOrder.fixed,
      );

      expect(Game.fromMap(game.toMap()).startingOrder, StartingOrder.fixed);
    });

    test('reads rows written before the starting order column existed', () {
      final map = Game(startScore: 301, createdAt: createdAt).toMap()
        ..remove('starting_order');

      // Those games were always shuffled, so random is the honest default.
      expect(Game.fromMap(map).startingOrder, StartingOrder.random);
    });

    test('carries the starting order through copyWith', () {
      final game = Game(
        startScore: 501,
        createdAt: createdAt,
        startingOrder: StartingOrder.fixed,
      );

      expect(
        game.copyWith(finishedAt: createdAt).startingOrder,
        StartingOrder.fixed,
      );
    });
  });
}
