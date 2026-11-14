import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/services/b74_team_match_contract.dart';
import 'package:dartscore_app/services/b74_team_revision_policy.dart';
import 'package:dartscore_app/services/competition_match_catalog.dart';
import 'package:dartscore_app/services/competition_match_inbox.dart';
import 'package:dartscore_app/services/competition_sync_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

Map<String, dynamic> competitionPacket(String matchId) => {
  'type': CompetitionSyncContract.type,
  'version': CompetitionSyncContract.version,
  'matchId': matchId,
  'division': 'Eredivisie',
  'home': {'id': 'h-$matchId', 'name': 'Home'},
  'away': {'id': 'a-$matchId', 'name': 'Away'},
  'startingScore': 501,
  'singles': [
    for (var i = 1; i <= 4; i++)
      {
        'slot': i,
        'homePlayer': {
          'id': 'h-$matchId-$i',
          'name': 'Home $i',
          'bondNumber': 'H-$matchId-$i',
        },
        'awayPlayer': {
          'id': 'a-$matchId-$i',
          'name': 'Away $i',
          'bondNumber': 'A-$matchId-$i',
        },
      },
  ],
};

Map<String, dynamic> lockedPacket(String matchId) => {
  'type': 'b74.competition.match-locked.v1',
  'version': 1,
  'matchId': matchId,
  'closedAt': 1793548800000,
  'homeWins': 5,
  'awayWins': 4,
};

Map<String, dynamic> teamPacket(String matchId, {required String kind}) {
  final beer = kind == 'beer1001';
  final count = beer ? 4 : 2;

  return {
    'type': B74TeamMatchContract.type,
    'version': 1,
    'matchId': matchId,
    'gameId': '$matchId-$kind-1',
    'revision': 1,
    'kind': kind,
    'slot': 1,
    'startingScore': beer ? 1001 : 701,
    'bestOf': beer ? 1 : 5,
    'startPolicy': 'home',
    'home': {
      'teamId': 'home-$matchId',
      'teamName': 'Thuis',
      'players': [
        for (var i = 1; i <= count; i++)
          {
            'playerId': 'h-$matchId-$i',
            'name': 'Thuis $i',
            'bondNumber': 'H-$matchId-$i',
            'position': i,
          },
      ],
    },
    'away': {
      'teamId': 'away-$matchId',
      'teamName': 'Uit',
      'players': [
        for (var i = 1; i <= count; i++)
          {
            'playerId': 'a-$matchId-$i',
            'name': 'Uit $i',
            'bondNumber': 'A-$matchId-$i',
            'position': i,
          },
      ],
    },
  };
}

void main() {
  group('C1B11 wedstrijdarchief en RETAIN zichtbaarheid', () {
    useInMemoryDatabase();

    test(
      'actief naar archief naar RETAIN; andere wedstrijd blijft zichtbaar',
      () async {
        final helper = DbHelper.instance;
        final database = await helper.db;
        final inbox = CompetitionMatchInbox();
        final catalog = CompetitionMatchCatalog();

        const removedMatch = 'archive-retain-a';
        const otherMatch = 'archive-retain-b';

        // Import two independent, valid competition matches.
        for (final matchId in [removedMatch, otherMatch]) {
          expect(
            await inbox.receive(
              CompetitionSyncContract.encode(competitionPacket(matchId)),
            ),
            isTrue,
          );
        }

        Future<List<String>> visibleIds({bool archived = false}) async {
          final matches = await catalog.load(archived: archived);
          return matches.map((match) => match.id).toList();
        }

        // Both matches initially belong to the active overview.
        expect(await visibleIds(), containsAll([removedMatch, otherMatch]));
        expect(await visibleIds(archived: true), isEmpty);

        // MATCH_LOCKED archives only the selected match.
        expect(
          await helper.receiveMatchLocked(lockedPacket(removedMatch)),
          'stored',
        );

        expect(await visibleIds(), [otherMatch]);
        expect(await visibleIds(archived: true), [removedMatch]);

        // Explicitly authorized RETAIN operation.
        await helper.stageAdminDeletionIntent(
          matchId: removedMatch,
          revision: 1,
          scope: 'official',
          statisticsMode: 'retain',
          authorizationId: 'auth-archive-retain-a',
        );

        expect(
          await helper.retainStagedAdminMatchForVerifiedCoordinator(
            matchId: removedMatch,
            revision: 1,
            authorizationId: 'auth-archive-retain-a',
          ),
          'retained',
        );

        // The administratively deleted match must not appear anywhere.
        expect(await visibleIds(), [otherMatch]);
        expect(await visibleIds(archived: true), isEmpty);

        // RETAIN preserves source data, including imported players.
        expect(
          await database.query(
            'competition_inbox',
            where: 'match_id = ?',
            whereArgs: [removedMatch],
          ),
          hasLength(1),
        );

        // Both imported matches use unique external player identities.
        // RETAIN must preserve all their player links.
        expect(await database.query('competition_player_links'), hasLength(16));

        // A completed RETAIN tombstone drives catalog visibility.
        final tombstones = await database.query(
          'competition_deletion_tombstones',
          where: 'match_id = ?',
          whereArgs: [removedMatch],
        );

        expect(tombstones, hasLength(1));
        expect(tombstones.single['retain_official_statistics'], 1);
        expect(tombstones.single['cleaned_at'], isNotNull);

        // The other competition match remains untouched.
        expect(
          await database.query(
            'competition_inbox',
            where: 'match_id = ?',
            whereArgs: [otherMatch],
          ),
          hasLength(1),
        );
      },
    );

    for (final kind in ['doubles701', 'beer1001']) {
      test(
        '$kind: actief naar archief naar RETAIN; andere wedstrijd blijft zichtbaar',
        () async {
          final helper = DbHelper.instance;
          final database = await helper.db;
          final catalog = CompetitionMatchCatalog();

          final removedMatch = 'archive-retain-$kind-a';
          final otherMatch = 'archive-retain-$kind-b';
          final removedGameId = '$removedMatch-$kind-1';

          // Import two independent team matches through the real inbox.
          for (final matchId in [removedMatch, otherMatch]) {
            final packet = teamPacket(matchId, kind: kind);

            expect(
              await helper.receiveCompetitionTeamMatch(
                B74TeamMatchContract.encode(packet),
              ),
              B74TeamRevisionDecision.create,
            );
          }

          Future<List<String>> visibleIds({bool archived = false}) async {
            final matches = kind == 'doubles701'
                ? await catalog.loadDoubles(archived: archived)
                : await catalog.loadBeers(archived: archived);

            return matches.map((match) => match.matchId).toList();
          }

          // Both matches are initially active.
          expect(await visibleIds(), containsAll([removedMatch, otherMatch]));
          expect(await visibleIds(archived: true), isEmpty);

          // MATCH_LOCKED moves only the selected match to the archive.
          expect(
            await helper.receiveMatchLocked(lockedPacket(removedMatch)),
            'stored',
          );

          expect(await visibleIds(), [otherMatch]);
          expect(await visibleIds(archived: true), [removedMatch]);

          // RETAIN requires an official singles match source.
          // Import the matching competition envelope before authorization.
          final inbox = CompetitionMatchInbox();
          expect(
            await inbox.receive(
              CompetitionSyncContract.encode(competitionPacket(removedMatch)),
            ),
            isTrue,
          );

          await helper.stageAdminDeletionIntent(
            matchId: removedMatch,
            revision: 1,
            scope: 'official',
            statisticsMode: 'retain',
            authorizationId: 'auth-$kind-retain',
          );

          expect(
            await helper.retainStagedAdminMatchForVerifiedCoordinator(
              matchId: removedMatch,
              revision: 1,
              authorizationId: 'auth-$kind-retain',
            ),
            'retained',
          );

          // RETAIN hides the match from both catalog views.
          expect(await visibleIds(), [otherMatch]);
          expect(await visibleIds(archived: true), isEmpty);

          // The source team match must still exist.
          final source = await database.query(
            'competition_team_inbox',
            where: 'game_id = ?',
            whereArgs: [removedGameId],
          );

          expect(source, hasLength(1));
          expect(source.single['match_id'], removedMatch);

          // The completed tombstone drives visibility.
          final tombstones = await database.query(
            'competition_deletion_tombstones',
            where: 'match_id = ?',
            whereArgs: [removedMatch],
          );

          expect(tombstones, hasLength(1));
          expect(tombstones.single['retain_official_statistics'], 1);
          expect(tombstones.single['cleaned_at'], isNotNull);

          // The unrelated match remains in the inbox.
          expect(
            await database.query(
              'competition_team_inbox',
              where: 'match_id = ?',
              whereArgs: [otherMatch],
            ),
            hasLength(1),
          );
        },
      );
    }
  });
}
