import 'dart:convert';

import '../database/db_helper.dart';
import 'b74_doubles_701.dart';
import 'b74_doubles_checkout.dart';
import 'b74_team_match_contract.dart';
import 'competition_team_rules_guard.dart';

/// Durable 701 doubles session. Each command is validated by replaying the
/// saved journal before an atomic append; an unsuccessful write changes no
/// in-memory state. The UI must reload after every accepted command.
class B74DoublesSession {
  B74DoublesSession._(
    this.gameId,
    this.bestOf,
    this.startTeam,
    this.openingBullRequired,
    this.events,
    this.engine,
  );

  final String gameId;
  final int bestOf;
  final int startTeam;
  final bool openingBullRequired;
  final List<String> events;
  final B74Doubles701 engine;
  int get startingScore => engine.startingScore;
  int get playersPerTeam => engine.playersPerTeam;
  String get checkIn => engine.checkIn;

  static Future<B74DoublesSession> load(String gameId) async {
    final inbox = await DbHelper.instance.competitionTeamMatch(gameId);
    if (inbox == null || !{'doubles701', 'beer1001'}.contains(inbox['kind'])) {
      throw StateError('701-koppelwedstrijd niet gevonden');
    }
    final packet = B74TeamMatchContract.decode(inbox['payload'] as String);
    CompetitionTeamRulesGuard.validateForCurrentEngine(packet);
    final policy = packet['startPolicy'] as String;
    // The initial bull policy requires an explicit selection in the UI.
    // For subsequent legs, the core proposes alternation from that choice.
    final saved = await DbHelper.instance.competitionDoublesEvents(gameId);
    int? initialTeam;
    if (policy == 'home') initialTeam = 0;
    if (policy == 'away') initialTeam = 1;
    if (policy == 'bull' && saved.isNotEmpty) {
      final first = jsonDecode(saved.first) as Map<String, dynamic>;
      if (first['type'] != 'starter' || first['viaBull'] != true) {
        throw StateError('Eerste leg vereist bullwinnaar');
      }
      initialTeam = first['team'] as int;
    }
    final engine = B74Doubles701(
      starterTeam: initialTeam ?? 0,
      bestOf: packet['bestOf'] as int,
      startingScore: packet['startingScore'] as int,
      playersPerTeam: (packet['kind'] == 'beer1001') ? 4 : 2,
      checkIn: packet['checkIn'] as String? ?? 'straight',
    );
    // A correction invalidates exactly one earlier visit while preserving the
    // append-only audit trail. Replay all other events deterministically.
    final decoded = saved
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .toList();
    final revoked = <int>{};
    final overrides = <int, Map<String, dynamic>>{};
    for (var i = 0; i < decoded.length; i++) {
      final event = decoded[i];
      if (event['type'] == 'correctVisit') {
        final target = event['targetSequence'];
        if (target is! int ||
            target < 0 ||
            target >= i ||
            decoded[target]['type'] != 'visit' ||
            revoked.contains(target)) {
          throw StateError('Ongeldige 701-scorecorrectie');
        }
        overrides[target] = event;
      }
      if (event['type'] == 'undoVisit') {
        final starterSequence = event['starterSequence'];
        if (starterSequence != null) {
          if (starterSequence is! int ||
              starterSequence < 0 ||
              starterSequence >= i ||
              decoded[starterSequence]['type'] != 'starter' ||
              !revoked.add(starterSequence)) {
            throw StateError('Ongeldige 701-startercorrectie');
          }
        }
        final target = event['targetSequence'];
        if (target is! int ||
            target < 0 ||
            target >= i ||
            decoded[target]['type'] != 'visit' ||
            !revoked.add(target)) {
          throw StateError('Ongeldige 701-correctiehistorie');
        }
      }
    }
    // A corrected winning visit may invalidate the already-confirmed starter
    // of the following leg. Keep that starter in the audit trail, but ignore
    // it while replaying the restored previous leg.
    for (var i = 0; i < decoded.length; i++) {
      if (revoked.contains(i)) continue;
      final event = overrides[i] == null
          ? decoded[i]
          : {...overrides[i]!, 'type': 'visit'};
      switch (event['type']) {
        case 'starter':
          final team = event['team'] as int;
          final viaBull = event['viaBull'] == true;
          if (engine.needsBull) {
            if (!viaBull) throw StateError('Beslissende leg zonder bull');
            engine.recordDecidingBullWinner(team);
          } else if (engine.leg == 1 && policy == 'bull') {
            if (!viaBull) throw StateError('Eerste leg zonder bull');
            engine.recordOpeningBullWinner(team);
          } else {
            if (viaBull) throw StateError('Onverwachte bull');
            engine.confirmLegStarter(team);
          }
        case 'undoVisit':
        case 'correctVisit':
          break;
        case 'visit':
          if (event['checkoutDart'] != null &&
              (event['validCheckout'] != true ||
                  event['checkoutDart'] is! int ||
                  (event['checkoutDart'] as int) < 1 ||
                  (event['checkoutDart'] as int) > 3)) {
            throw StateError('Ongeldige opgeslagen checkoutdart');
          }
          if (event['checkoutDarts'] != null &&
              !B74DoublesCheckout.valid(
                remaining: engine.remaining[engine.currentVisit.team],
                score: event['score'] as int,
                darts: (event['checkoutDarts'] as List).cast<String>(),
              )) {
            throw StateError('Ongeldige opgeslagen checkout');
          }
          engine.completeVisit(
            score: event['score'] as int,
            bust: event['bust'] as bool,
            validCheckout: event['validCheckout'] as bool,
            openingDouble: event['openingDouble'] as int?,
            openingDart: event['openingDart'] as int?,
          );
        default:
          throw StateError('Onbekend 701-event');
      }
    }
    return B74DoublesSession._(
      gameId,
      packet['bestOf'] as int,
      initialTeam ?? 0,
      policy == 'bull',
      saved,
      engine,
    );
  }

  Future<void> confirmStarter(int team, {bool viaBull = false}) async {
    final inbox = await DbHelper.instance.competitionTeamMatch(gameId);
    if (inbox == null) throw StateError('Wedstrijd ontbreekt');
    final packet = B74TeamMatchContract.decode(inbox['payload'] as String);
    CompetitionTeamRulesGuard.validateForCurrentEngine(packet);
    final firstBull = engine.leg == 1 && packet['startPolicy'] == 'bull';
    if (engine.needsBull) {
      if (!viaBull) throw StateError('Bull verplicht');
    } else if (firstBull) {
      if (!viaBull) throw StateError('Eerste leg: bull verplicht');
    } else if (viaBull) {
      throw StateError('Geen bull vereist');
    }
    // Validate before persisting, using a fresh replay after this command.
    if (!engine.awaitingStarter || (team != 0 && team != 1)) {
      throw StateError('Starterselectie ongeldig');
    }
    await DbHelper.instance.appendCompetitionDoublesEvent(
      gameId: gameId,
      expectedSequence: events.length,
      eventJson: jsonEncode({
        'type': 'starter',
        'team': team,
        'viaBull': viaBull,
      }),
      isVisit: false,
    );
  }

  Future<void> completeVisit({
    required int score,
    bool bust = false,
    bool validCheckout = false,
    List<String>? checkoutDarts,
    int? checkoutDart,
    int? openingDouble,
    int? openingDart,
  }) async {
    // Validate against a fresh copy of the deterministic score core first.
    final fresh = await B74DoublesSession.load(gameId);
    if (fresh.events.length != events.length) {
      throw StateError('Wedstrijd gewijzigd: opnieuw laden');
    }
    if (validCheckout &&
        checkoutDart != null &&
        (checkoutDart < 1 || checkoutDart > 3)) {
      throw StateError('Checkoutdart moet 1, 2 of 3 zijn');
    }
    if (validCheckout &&
        checkoutDart == null &&
        (checkoutDarts == null ||
            !B74DoublesCheckout.valid(
              remaining: fresh.engine.remaining[fresh.engine.currentVisit.team],
              score: score,
              darts: checkoutDarts,
            ))) {
      throw StateError('Checkout per dart ongeldig');
    }
    if (!validCheckout && (checkoutDarts != null || checkoutDart != null)) {
      throw StateError('Dartgegevens zonder checkout');
    }
    fresh.engine.completeVisit(
      score: score,
      bust: bust,
      validCheckout: validCheckout,
      openingDouble: openingDouble,
      openingDart: openingDart,
    );
    await DbHelper.instance.appendCompetitionDoublesEvent(
      gameId: gameId,
      expectedSequence: events.length,
      eventJson: jsonEncode({
        'type': 'visit',
        'score': score,
        'bust': bust,
        'validCheckout': validCheckout,
        if (openingDouble != null) 'openingDouble': openingDouble,
        if (openingDart != null) 'openingDart': openingDart,
        if (checkoutDarts != null) 'checkoutDarts': checkoutDarts,
        if (checkoutDart != null) 'checkoutDart': checkoutDart,
      }),
      isVisit: true,
    );
  }

  /// Undo the most recent visit, including a winning checkout. The journal is
  /// never truncated: a compensating event makes replay restore the old state.
  /// Only the last effective event may be a visit (not a starter selection).
  Future<void> undoLastVisit() async {
    final fresh = await B74DoublesSession.load(gameId);
    if (fresh.events.length != events.length) {
      throw StateError('Wedstrijd gewijzigd: opnieuw laden');
    }
    final revoked = <int>{};
    for (final raw in events) {
      final event = jsonDecode(raw) as Map<String, dynamic>;
      if (event['type'] == 'undoVisit') {
        revoked.add(event['targetSequence'] as int);
        if (event['starterSequence'] is int) {
          revoked.add(event['starterSequence'] as int);
        }
      }
    }
    // A leg may already have its next starter confirmed, but no visits yet.
    // Undoing the previous checkout must also revoke that starter atomically.
    int? trailingStarter;
    int? last;
    for (var i = events.length - 1; i >= 0; i--) {
      if (revoked.contains(i)) continue;
      final event = jsonDecode(events[i]) as Map<String, dynamic>;
      if (event['type'] == 'undoVisit' || event['type'] == 'correctVisit') {
        continue;
      }
      if (event['type'] == 'starter' && trailingStarter == null) {
        trailingStarter = i;
        continue;
      }
      if (event['type'] == 'visit') {
        last = i;
      }
      break;
    }
    if (last == null) throw StateError('Geen laatste beurt om te corrigeren');
    if (trailingStarter != null) {
      // Only a checkout can be followed by the next leg's starter.
      final previous = jsonDecode(events[last]) as Map<String, dynamic>;
      if (previous['validCheckout'] != true) {
        throw StateError('Starter kan niet worden teruggedraaid');
      }
    }
    await DbHelper.instance.appendCompetitionDoublesEvent(
      gameId: gameId,
      expectedSequence: events.length,
      eventJson: jsonEncode({
        'type': 'undoVisit',
        'targetSequence': last,
        if (trailingStarter != null) 'starterSequence': trailingStarter,
      }),
      isVisit: false,
    );
  }

  /// The most recent three effective visits in the current leg. A correction
  /// never silently changes a previous leg or an already confirmed starter.
  List<({int sequence, int score, bool bust})> get correctableVisits {
    if (engine.awaitingStarter || engine.winner != null) return [];
    final revoked = <int>{};
    final overrides = <int, Map<String, dynamic>>{};
    for (final raw in events) {
      final event = jsonDecode(raw) as Map<String, dynamic>;
      if (event['type'] == 'undoVisit') {
        revoked.add(event['targetSequence'] as int);
        if (event['starterSequence'] is int) {
          revoked.add(event['starterSequence'] as int);
        }
      }
      if (event['type'] == 'correctVisit')
        overrides[event['targetSequence'] as int] = event;
    }
    final result = <({int sequence, int score, bool bust})>[];
    for (var i = events.length - 1; i >= 0 && result.length < 3; i--) {
      final original = jsonDecode(events[i]) as Map<String, dynamic>;
      if (original['type'] == 'starter' && !revoked.contains(i)) break;
      if (original['type'] != 'visit' || revoked.contains(i)) continue;
      final visit = overrides[i] ?? original;
      result.add((
        sequence: i,
        score: visit['score'] as int,
        bust: visit['bust'] as bool,
      ));
    }
    return result;
  }

  /// Append-only replacement of one of the last three visits. Validate the
  /// entire replay before persisting; later visits may make an edit invalid.
  Future<void> correctVisit(
    int sequence, {
    required int score,
    bool bust = false,
  }) async {
    if (!correctableVisits.any((v) => v.sequence == sequence)) {
      throw StateError(
        'Alleen de laatste drie beurten in deze leg zijn corrigeerbaar',
      );
    }
    if (score < 0 || score > 180)
      throw StateError('Score moet tussen 0 en 180 liggen');
    final fresh = await B74DoublesSession.load(gameId);
    if (fresh.events.length != events.length)
      throw StateError('Wedstrijd gewijzigd: opnieuw laden');
    if (checkIn == 'double') {
      throw StateError('Double In: gebruik TERUGDRAAIEN en voer de beurt opnieuw in');
    }
    final original = jsonDecode(events[sequence]) as Map<String, dynamic>;
    if (original['validCheckout'] == true) {
      throw StateError('Gebruik terugdraaien voor een winnende checkout');
    }
    final replacement = {
      'type': 'correctVisit',
      'targetSequence': sequence,
      'score': bust ? 0 : score,
      'bust': bust,
      'validCheckout': false,
    };
    // Persist only if the new state can be replayed successfully. In case of
    // a failed replay the append is compensated with a new correction event.
    // Avoid writing invalid history by simulating the event list in memory.
    final candidate = [...events, jsonEncode(replacement)];
    _validateCorrectionReplay(candidate);
    await DbHelper.instance.appendCompetitionDoublesEvent(
      gameId: gameId,
      expectedSequence: events.length,
      eventJson: jsonEncode(replacement),
      isVisit: false,
    );
  }

  void _validateCorrectionReplay(List<String> candidate) {
    final decoded = candidate
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .toList();
    final replacements = <int, Map<String, dynamic>>{};
    final revoked = <int>{};
    for (final e in decoded) {
      if (e['type'] == 'undoVisit') {
        revoked.add(e['targetSequence'] as int);
        if (e['starterSequence'] is int) {
          revoked.add(e['starterSequence'] as int);
        }
      }
      if (e['type'] == 'correctVisit')
        replacements[e['targetSequence'] as int] = e;
    }
    final core = B74Doubles701(
      starterTeam: startTeam, bestOf: bestOf,
      startingScore: startingScore, playersPerTeam: playersPerTeam,
      checkIn: checkIn,
    );
    for (var i = 0; i < decoded.length; i++) {
      if (revoked.contains(i)) continue;
      final e = replacements[i] == null
          ? decoded[i]
          : {...replacements[i]!, 'type': 'visit'};
      switch (e['type']) {
        case 'starter':
          final team = e['team'] as int;
          if (core.needsBull) {
            core.recordDecidingBullWinner(team);
          } else if (core.leg == 1 && openingBullRequired) {
            core.recordOpeningBullWinner(team);
          } else {
            core.confirmLegStarter(team);
          }
        case 'visit':
          core.completeVisit(
            score: e['score'] as int,
            bust: e['bust'] as bool,
            validCheckout: e['validCheckout'] as bool,
            openingDouble: e['openingDouble'] as int?,
            openingDart: e['openingDart'] as int?,
          );
        case 'correctVisit':
        case 'undoVisit':
          break;
      }
    }
  }
}
