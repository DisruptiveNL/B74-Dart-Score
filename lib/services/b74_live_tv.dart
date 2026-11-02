import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/game_provider.dart';
import '../models/dart_throw.dart';
import 'b74_doubles_session.dart';
import 'b74_doubles_live_stats.dart';
import 'b74_doubles_701.dart';

/// Independent TV-only connection. Never substitutes for Dashboard pairing.
class B74LiveTv {
  B74LiveTv._();
  static final instance = B74LiveTv._();
  static const _secure = FlutterSecureStorage();
  static const _registrationKey = 'b74_live_tv_registration_v1';
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;
  bool _connecting = false;
  String? _host;
  int? _port;
  String? _fingerprint;
  String? _deviceId;
  String? _secret;
  int? _expiresAt;
  WebSocket? _socket;
  StreamSubscription? _messages;
  GameProvider? _provider;
  B74DoublesSession? _doublesSession;
  bool _doublesCelebrate180 = false;
  List<String>? _doublesNamesHome;
  List<String>? _doublesNamesAway;
  String? _doublesHomeTeam;
  String? _doublesAwayTeam;
  String? _session;
  int _sequence = 0;
  int? _last180ThrowId;
  bool get connected => _socket?.readyState == WebSocket.open;

  /// Attach the current X01 match without changing the paired TV socket.
  /// The previous match listener is removed when switching matches.
  void attachGame(GameProvider provider) {
    _doublesSession = null;
    if (identical(_provider, provider)) {
      _publish();
      return;
    }
    _provider?.removeListener(_publish);
    _provider = provider;
    if (connected) {
      provider.addListener(_publish);
      _last180ThrowId = null;
      _publish();
    }
  }


  /// Publish the competition doubles/beer-game journal over the SAME TV socket.
  /// The UI calls this after loading the session, including corrections/undo.
  void attachDoubles(B74DoublesSession session, {
    required String homeTeam,
    required String awayTeam,
    required List<String> homePlayers,
    required List<String> awayPlayers,
  }) {
    _provider?.removeListener(_publish);
    _provider = null;
    final previous = _doublesSession;
    _doublesCelebrate180 = previous != null &&
      previous.gameId == session.gameId &&
      session.events.length > previous.events.length &&
      session.events.isNotEmpty &&
      (() {
        final last = jsonDecode(session.events.last) as Map<String, dynamic>;
        return last['type'] == 'visit' && last['bust'] != true && last['score'] == 180;
      })();
    _doublesSession = session;
    _doublesHomeTeam = homeTeam;
    _doublesAwayTeam = awayTeam;
    _doublesNamesHome = List.of(homePlayers);
    _doublesNamesAway = List.of(awayPlayers);
    _publish();
  }

  /// Restore the registered receiver after app restart. A registration is
  /// never renewed by reconnecting; the receiver enforces the original expiry.
  Future<void> restore() async {
    if (connected || _connecting || _manualDisconnect) return;
    final stored = await _secure.read(key: _registrationKey);
    if (stored == null) return;
    try {
      final data = jsonDecode(stored) as Map<String, dynamic>;
      _host = data['host'] as String;
      _port = data['port'] as int;
      _fingerprint = data['fingerprint'] as String;
      _deviceId = data['deviceId'] as String;
      _secret = data['secret'] as String;
      _expiresAt = data['expiresAt'] as int;
      if (!_registrationValid) {
        await _clearRegistration();
        return;
      }
      await _resume();
    } catch (_) {
      // Invalid/obsolete secure-storage contents must never trigger ws fallback.
      await _clearRegistration();
    }
  }

  bool get _registrationValid =>
      _host != null && InternetAddress.tryParse(_host!) != null &&
      _port != null && _port! > 0 && _port! <= 65535 &&
      _fingerprint != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(_fingerprint!) &&
      _deviceId != null && _deviceId!.isNotEmpty &&
      _secret != null && _secret!.isNotEmpty &&
      _expiresAt != null && DateTime.now().millisecondsSinceEpoch < _expiresAt!;

  Future<void> connect(String qr, [GameProvider? provider]) async {
    final uri = Uri.parse(qr);
    final q = uri.queryParameters;
    final host = q['host'];
    final token = q['token'];
    final fingerprint = q['sha256']?.toLowerCase();
    final port = int.tryParse(q['port'] ?? '');
    if (uri.scheme != 'b74-live' || uri.host != 'pair' || q['v'] != '1' ||
        host == null || InternetAddress.tryParse(host) == null ||
        port == null || port < 1 || port > 65535 ||
        token == null || token.isEmpty ||
        fingerprint == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      throw const FormatException('Ongeldige B74 Live QR-code');
    }
    await disconnect();
    _manualDisconnect = false;
    _host = host;
    _port = port;
    _fingerprint = fingerprint;
    _deviceId = null;
    _secret = null;
    _expiresAt = null;
    if (provider != null) _provider = provider;
    await _open('/pair', {'token': token});
  }

  Future<void> _resume() async {
    if (!_registrationValid || _connecting || connected || _manualDisconnect) return;
    await _open('/resume', {'device': _deviceId!, 'secret': _secret!});
  }

  Future<void> _open(String path, Map<String, String> params) async {
    if (_connecting) return;
    _connecting = true;
    var certificateVerified = false;
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.badCertificateCallback = (cert, _, __) {
      final ok = sha256.convert(cert.der).toString() == _fingerprint;
      if (ok) certificateVerified = true;
      return ok;
    };
    try {
      final ws = await WebSocket.connect(
        Uri(scheme: 'wss', host: _host, port: _port, path: path,
          queryParameters: params).toString(),
        customClient: client,
      ).timeout(const Duration(seconds: 8));
      if (!certificateVerified) {
        await ws.close();
        throw StateError('TV-certificaat niet geverifieerd');
      }
      _reconnectTimer?.cancel();
      _socket = ws;
      _session = DateTime.now().microsecondsSinceEpoch.toString();
      _sequence = 0;
      _last180ThrowId = null;
      _provider?.removeListener(_publish);
      _provider?.addListener(_publish);
      _messages = ws.listen((message) async {
        if (message is! String) return;
        try {
          final envelope = jsonDecode(message) as Map<String, dynamic>;
          if (envelope['protocol'] != 'b74.live.score' ||
              envelope['version'] != 1 ||
              envelope['type'] != 'device.registration') return;
          final payload = envelope['payload'] as Map<String, dynamic>;
          final deviceId = payload['deviceId'] as String;
          final secret = payload['secret'] as String;
          final expiresAt = payload['expiresAt'] as int;
          if (deviceId.isEmpty || secret.isEmpty ||
              expiresAt <= DateTime.now().millisecondsSinceEpoch) return;
          _deviceId = deviceId;
          _secret = secret;
          _expiresAt = expiresAt;
          await _secure.write(key: _registrationKey, value: jsonEncode({
            'host': _host, 'port': _port, 'fingerprint': _fingerprint,
            'deviceId': deviceId, 'secret': secret, 'expiresAt': expiresAt,
          }));
        } catch (_) { /* Other messages (ACKs) are not registration messages. */ }
      }, onDone: () => _onSocketClosed(ws),
          onError: (_) => _onSocketClosed(ws), cancelOnError: true);
      _doublesCelebrate180 = false;
      _publish(); // Full snapshot, new session/sequence after every reconnect.
    } finally {
      _connecting = false;
      client.close(force: false);
    }
  }

  void _onSocketClosed(WebSocket ws) {
    if (!identical(_socket, ws)) return;
    _socket = null;
    _provider?.removeListener(_publish);
    if (_manualDisconnect || !_registrationValid) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      if (_manualDisconnect) return;
      try { await _resume(); } catch (_) {
        if (!_manualDisconnect && _registrationValid) {
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(const Duration(seconds: 10), _retryResume);
        }
      }
    });
  }

  void _retryResume() async {
    if (_manualDisconnect || connected || !_registrationValid) return;
    try { await _resume(); } catch (_) {
      if (!_manualDisconnect && _registrationValid) {
        _reconnectTimer = Timer(const Duration(seconds: 10), _retryResume);
      }
    }
  }

  Future<void> _clearRegistration() async {
    _deviceId = null;
    _secret = null;
    _expiresAt = null;
    await _secure.delete(key: _registrationKey);
  }

  void _publish() {
    if (_doublesSession != null) {
      _publishDoubles();
      return;
    }
    final p = _provider;
    final ws = _socket;
    if (p == null || ws == null || ws.readyState != WebSocket.open || p.game == null || p.playerStates.length != 2) return;
    final game = p.game!;
    if (![501, 701, 1001].contains(game.startScore)) return;
    final states = p.playerStates;
    final active = p.currentPlayerIndex;
    final latest = p.allThrows().where((t) => t.score == 180 && !t.bust).toList();
    final last180 = latest.isEmpty ? null : latest.last;
    final new180 = last180 != null && last180.id != null && last180.id != _last180ThrowId;
    // On initial connection show current state, never celebrate historical 180s.
    final celebrate = _sequence > 0 && new180 &&
        p.allThrows().isNotEmpty && p.allThrows().last.id == last180.id;
    _last180ThrowId = last180?.id;
    final mode = switch (game.startScore) { 701 => 'DOUBLES_701', 1001 => 'BEERGAME_1001', _ => 'SINGLES_501' };
    final sides = List.generate(2, (i) {
      final s = states[i];
      // These are slot-level visits: player for singles, combined for teams.
      // Busts count as zero points, but still consume darts.
      final visits = s.throws;
      final firstNine = _firstNineAverage(visits);
      final lastThree = visits.reversed.take(3)
          .map((t) => t.bust ? 0 : t.score).toList();
      return {
        'id': i == 0 ? 'home' : 'away',
        'displayName': s.displayName,
        'playerNames': s.players.map((v) => v.name).toList(),
        'remaining': i == active ? p.liveDisplayRemaining : s.remaining,
        'legsWon': s.legsWon,
        'stats': {
          'threeDartAverage': s.totalDarts == 0 ? null : s.average,
          'firstNineAverage': firstNine,
          'lastThreeVisits': lastThree,
          'dartsThrown': s.totalDarts,
          'highestVisit': visits.isEmpty ? null : visits.map((t) => t.bust ? 0 : t.score).reduce((a,b) => a > b ? a : b),
          'oneEighties': visits.where((t) => !t.bust && t.score == 180).length,
          'oneForties': visits.where((t) => !t.bust && t.score >= 140).length,
          'hundreds': visits.where((t) => !t.bust && t.score >= 100).length,
        },
      };
    });
    ws.add(jsonEncode({
      'protocol': 'b74.live.score', 'version': 1, 'type': 'score.snapshot',
      'sessionId': _session, 'laneId': 'lane-1',
      'matchId': 'x01-${game.id ?? 'current'}', 'sequence': ++_sequence,
      'payload': {
        'game': {'mode': mode}, 'displayState': p.gameOver ? 'MATCH_COMPLETE' : 'LIVE',
        'sides': sides, 'activeSideId': active == 0 ? 'home' : 'away',
        'activePlayerName': p.currentPlayerState.player.name,
        'statusText': '',
        if (celebrate) 'celebration': {'type': '180', 'trigger': true},
      },
    }));
  }

  void _publishDoubles() {
    final s = _doublesSession;
    final ws = _socket;
    if (s == null || ws == null || ws.readyState != WebSocket.open) return;
    final engine = s.engine;
    final stats = B74DoublesLiveStats.fromEvents(s.events,
      startTeam: s.startTeam, bestOf: s.bestOf,
      openingBullRequired: s.openingBullRequired,
      startingScore: s.startingScore, playersPerTeam: s.playersPerTeam,
      checkIn: s.checkIn);
    // Reconstruct team visits chronologically (also after undo/correction).
    final decoded = s.events.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    final revoked = <int>{};
    final corrections = <int, Map<String, dynamic>>{};
    for (final e in decoded) {
      if (e['type'] == 'undoVisit') {
        revoked.add(e['targetSequence'] as int);
        if (e['starterSequence'] is int) revoked.add(e['starterSequence'] as int);
      } else if (e['type'] == 'correctVisit') {
        corrections[e['targetSequence'] as int] = e;
      }
    }
    final replay = B74Doubles701(starterTeam: s.startTeam, bestOf: s.bestOf,
      startingScore: s.startingScore, playersPerTeam: s.playersPerTeam,
      checkIn: s.checkIn);
    final teamVisits = [<({int score, int darts})>[], <({int score, int darts})>[]];
    for (var i = 0; i < decoded.length; i++) {
      if (revoked.contains(i)) continue;
      final e = corrections[i] == null ? decoded[i] : {...corrections[i]!, 'type': 'visit'};
      switch (e['type']) {
        case 'starter':
          final team = e['team'] as int;
          if (replay.needsBull) {
            replay.recordDecidingBullWinner(team);
          } else if (replay.leg == 1 && s.openingBullRequired) {
            replay.recordOpeningBullWinner(team);
          } else {
            replay.confirmLegStarter(team);
          }
        case 'visit':
          final turn = replay.currentVisit;
          final checkoutDart = e['checkoutDart'];
          final checkoutDarts = e['checkoutDarts'];
          final darts = e['validCheckout'] == true && checkoutDart is int
              ? checkoutDart : e['validCheckout'] == true && checkoutDarts is List
              ? checkoutDarts.length : 3;
          teamVisits[turn.team].add((score: e['bust'] == true ? 0 : e['score'] as int, darts: darts));
          replay.completeVisit(score: e['score'] as int, bust: e['bust'] as bool,
            validCheckout: e['validCheckout'] as bool,
            openingDouble: e['openingDouble'] as int?, openingDart: e['openingDart'] as int?);
      }
    }
    final names = [_doublesNamesHome ?? <String>[], _doublesNamesAway ?? <String>[]];
    final teamNames = [_doublesHomeTeam ?? '', _doublesAwayTeam ?? ''];
    final sides = List.generate(2, (team) {
      final allScores = <int>[];
      var points = 0;
      var darts = 0;
      var hundreds = 0;
      var oneForties = 0;
      var oneEighties = 0;
      for (var player = 0; player < s.playersPerTeam; player++) {
        final ps = stats.player(team, player);
        points += ps.points;
        darts += ps.dartsThrown;
        hundreds += ps.hundreds;
        oneForties += ps.oneForties;
        oneEighties += ps.oneEighties;
        allScores.addAll(ps.scores);
      }
      return {
        'id': team == 0 ? 'home' : 'away',
        'displayName': s.playersPerTeam == 2 ? names[team].join(' + ') : teamNames[team],
        'playerNames': names[team],
        'remaining': engine.remaining[team],
        'legsWon': engine.legsWon[team],
        'stats': {
          'threeDartAverage': darts == 0 ? null : points * 3.0 / darts,
          'firstNineAverage': _teamFirstNine(teamVisits[team]),
          'lastThreeVisits': teamVisits[team].reversed.take(3).map((v) => v.score).toList(),
          'dartsThrown': darts,
          'highestVisit': allScores.isEmpty ? null : allScores.reduce((a,b) => a > b ? a : b),
          'oneEighties': oneEighties,
          'oneForties': oneForties,
          'hundreds': hundreds,
        },
      };
    });
    final active = engine.winner == null && !engine.awaitingStarter
        ? engine.currentVisit.team : null;
    final activeName = active == null ? '' :
      names[active].length > engine.currentVisit.player
          ? names[active][engine.currentVisit.player] : '';
    final celebrate = _doublesCelebrate180;
    _doublesCelebrate180 = false;
    ws.add(jsonEncode({
      'protocol': 'b74.live.score', 'version': 1, 'type': 'score.snapshot',
      'sessionId': _session, 'laneId': 'lane-1',
      'matchId': 'competition-${s.gameId}', 'sequence': ++_sequence,
      'payload': {
        'game': {'mode': s.startingScore == 1001 ? 'BEERGAME_1001' : 'DOUBLES_701'},
        'displayState': engine.winner != null ? 'MATCH_COMPLETE' : 'LIVE',
        'sides': sides,
        'activeSideId': active == 0 ? 'home' : active == 1 ? 'away' : null,
        'activePlayerName': activeName,
        'statusText': engine.awaitingStarter && engine.winner == null ? 'Kies starter' : '',
        if (celebrate) 'celebration': {'type': '180', 'trigger': true},
      },
    }));
  }

  static double? _teamFirstNine(List<({int score, int darts})> visits) {
    var darts = 0;
    var points = 0;
    for (final v in visits) {
      if (darts >= 9) break;
      if (v.darts <= 0 || darts + v.darts > 9) return null;
      darts += v.darts;
      points += v.score;
    }
    return darts == 0 ? null : points * 3.0 / darts;
  }

  /// The first nine *actual* darts of this slot, across the current match.
  /// A partially recorded visit contributes only its actual darts; where a
  /// visit straddles dart nine, individual hits are needed to split its score.
  /// Without them, return null rather than inventing a partial-visit score.
  static double? _firstNineAverage(List<DartThrow> visits) {
    var darts = 0;
    var points = 0;
    for (final visit in visits) {
      if (darts >= 9) break;
      final count = visit.dartsUsed;
      if (count <= 0) continue;
      if (darts + count > 9) return null;
      darts += count;
      points += visit.bust ? 0 : visit.score;
    }
    return darts == 0 ? null : points * 3.0 / darts;
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _provider?.removeListener(_publish);
    _provider = null;
    _doublesSession = null;
    await _clearRegistration();
    await _messages?.cancel();
    _messages = null;
    await _socket?.close();
    _socket = null;
  }
}
