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
          participants[player['id'] as String] = player;
        }
      }
      for (final entry in participants.entries) {
        final externalId = entry.key;
        final data = entry.value;
        final links = await txn.query(
          'competition_player_links',
          where: 'external_player_id = ?',
          whereArgs: [externalId],
        );
        if (links.isNotEmpty) continue;
        final bond = (data['bondNumber'] as String?)?.trim();
        // Do not merge based on a name or an unverified bond number.
        // An existing unlinked profile must be resolved explicitly.
        if (bond != null && bond.isNotEmpty) {
          final conflicts = await txn.query(
            'competition_player_links',
            where: 'bond_number = ?',
            whereArgs: [bond],
          );
          if (conflicts.isNotEmpty) {
            throw StateError(
              'Bondsnummer is gekoppeld aan een andere speler: $bond',
            );
          }
        }
        final name = (data['name'] as String).trim();
        final existingProfiles = await txn.query(
          'players',
          columns: ['id', 'name'],
          where: 'is_deleted = 0 AND bot_level IS NULL',
        );
        if (existingProfiles.any(
          (row) =>
              (row['name'] as String).trim().toLowerCase() ==
              name.toLowerCase(),
        )) {
          throw StateError(
            'Bestaande speler met dezelfde naam: $name. '
            'Koppel deze speler eerst handmatig om duplicaten te voorkomen.',
          );
        }
        final player = Player(
          name: data['name'] as String,
          favoriteDoubles: 'Bull',
        );
        final playerId = await txn.insert('players', player.toMap());
        await txn.insert('competition_player_links', {
          'external_player_id': externalId,
          'player_id': playerId,
          'bond_number': bond?.isEmpty == true ? null : bond,
          'source': 'competition_sync',
        });
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
