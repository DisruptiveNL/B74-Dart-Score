import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../providers/game_provider.dart';
import '../models/dart_throw.dart';

/// Independent TV-only connection. Never substitutes for Dashboard pairing.
class B74LiveTv {
  B74LiveTv._();
  static final instance = B74LiveTv._();
  WebSocket? _socket;
  StreamSubscription? _messages;
  GameProvider? _provider;
  String? _session;
  int _sequence = 0;
  int? _last180ThrowId;
  bool get connected => _socket?.readyState == WebSocket.open;

  /// Attach the current X01 match without changing the paired TV socket.
  /// The previous match listener is removed when switching matches.
  void attachGame(GameProvider provider) {
    if (identical(_provider, provider)) return;
    _provider?.removeListener(_publish);
    _provider = provider;
    if (connected) {
      provider.addListener(_publish);
      _last180ThrowId = null;
      _publish();
    }
  }


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
    var certificateVerified = false;
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.badCertificateCallback = (cert, _, __) {
      final ok = sha256.convert(cert.der).toString() == fingerprint;
      if (ok) certificateVerified = true;
      return ok;
    };
    try {
      final ws = await WebSocket.connect(
        Uri(scheme: 'wss', host: host, port: port, path: '/pair',
          queryParameters: {'token': token}).toString(),
        customClient: client,
      ).timeout(const Duration(seconds: 8));
      if (!certificateVerified) {
        await ws.close();
        throw StateError('TV-certificaat niet via QR geverifieerd');
      }
      _socket = ws;
      _provider = null;
      if (provider != null) attachGame(provider);
      _session = DateTime.now().microsecondsSinceEpoch.toString();
      _sequence = 0;
      _last180ThrowId = null;
      _messages = ws.listen((_) {}, onDone: () { _provider?.removeListener(_publish); _provider = null; _socket = null; });
      if (provider != null) _publish();
    } finally {
      client.close(force: false);
    }
  }

  void _publish() {
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
    _provider?.removeListener(_publish);
    _provider = null;
    await _messages?.cancel();
    _messages = null;
    await _socket?.close();
    _socket = null;
  }
}
