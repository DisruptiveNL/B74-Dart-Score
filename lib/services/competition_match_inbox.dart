import 'dart:convert';

import '../database/db_helper.dart';
import '../models/player.dart';
import 'competition_sync_contract.dart';

/// Durable, idempotent import of a frozen competition lineup.
/// Does not modify the existing player/stats sync protocol.
class CompetitionMatchInbox {
  CompetitionMatchInbox({DbHelper? helper})
    : _helper = helper ?? DbHelper.instance;
  final DbHelper _helper;

  /// Returns true for a new match, false for an identical replay.
  /// A changed snapshot for an existing match is rejected, not overwritten.
  Future<bool> receive(String json) async {
    final packet = CompetitionSyncContract.decode(json);
    final db = await _helper.db;
    return db.transaction((txn) async {
      final id = packet['matchId'] as String;
      final existing = await txn.query(
        'competition_inbox',
        where: 'match_id = ?',
        whereArgs: [id],
      );
      if (existing.isNotEmpty) {
        final old = CompetitionSyncContract.decode(
          existing.single['payload'] as String,
        );
        if (jsonEncode(old) != jsonEncode(packet)) {
          throw StateError('Conflicterende wedstrijdversie: $id');
        }
        return false;
      }

      final slots = packet['singles'] as List;
      final participants = <String, Map<String, dynamic>>{};
      for (final slot in slots) {
        final row = slot as Map<String, dynamic>;
        for (final side in ['homePlayer', 'awayPlayer']) {
          final player = row[side] as Map<String, dynamic>;
          final externalId = player['id'] as String;
          final previous = participants[externalId];
          if (previous != null &&
              ((previous['bondNumber'] as String?)?.trim() !=
                      (player['bondNumber'] as String?)?.trim() ||
                  previous['name'] != player['name'])) {
            throw StateError('Tegenstrijdige spelergegevens: $externalId');
          }
          participants[externalId] = player;
        }
      }

      for (final entry in participants.entries) {
        final externalId = entry.key;
        final data = entry.value;
        final bondValue = (data['bondNumber'] as String?)?.trim();
        final bond = bondValue == null || bondValue.isEmpty ? null : bondValue;
        final name = (data['name'] as String).trim();

        final byExternal = await txn.query(
          'competition_player_links',
          where: 'external_player_id = ?',
          whereArgs: [externalId],
        );
        final byBond = bond == null
            ? <Map<String, Object?>>[]
            : await txn.query(
                'competition_player_links',
                where: 'bond_number = ?',
                whereArgs: [bond],
              );

        int? playerId;
        if (byExternal.isNotEmpty) {
          playerId = byExternal.single['player_id'] as int;
          // An alias stores a NULL bond number. Resolve its canonical bond
          // through the shared local player, rather than trusting the name.
          final canonical = await txn.query(
            'competition_player_links',
            columns: ['bond_number'],
            where: 'player_id = ? AND bond_number IS NOT NULL',
            whereArgs: [playerId],
          );
          final registeredBond = canonical.isNotEmpty
              ? canonical.single['bond_number'] as String
              : null;
          if (registeredBond != null && bond != registeredBond) {
            throw StateError('Bondsnummer gewijzigd voor speler $externalId');
          }
          if (byBond.isNotEmpty && byBond.single['player_id'] != playerId) {
            throw StateError('Bondsnummer hoort bij een andere speler: $bond');
          }
          if (registeredBond == null && bond != null) {
            if (byBond.isNotEmpty) {
              throw StateError(
                'Bondsnummer hoort bij een andere speler: $bond',
              );
            }
            await txn.update(
              'competition_player_links',
              {'bond_number': bond},
              where: 'external_player_id = ?',
              whereArgs: [externalId],
            );
          }
        } else if (byBond.isNotEmpty) {
          playerId = byBond.single['player_id'] as int;
          // Preserve the original external ID for historical matches.
          // Only the canonical link carries the unique bond number.
          await txn.insert('competition_player_links', {
            'external_player_id': externalId,
            'player_id': playerId,
            'bond_number': null,
            'source': 'competition_sync',
          });
        } else {
          final player = Player(name: name, favoriteDoubles: 'Bull');
          playerId = await txn.insert('players', player.toMap());
          await txn.insert('competition_player_links', {
            'external_player_id': externalId,
            'player_id': playerId,
            'bond_number': bond,
            'source': 'competition_sync',
          });
        }

        // Updating a display name must never replace the local player row:
        // existing game references, preferences and statistics stay intact.
        await txn.update(
          'players',
          {'name': name},
          where: 'id = ? AND is_deleted = 0 AND bot_level IS NULL',
          whereArgs: [playerId],
        );
      }

      await txn.insert('competition_inbox', {
        'match_id': id,
        'payload': jsonEncode(packet),
        'received_at': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    });
  }
}
