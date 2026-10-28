import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/dart_throw.dart';
import 'incoming_file.dart'
    show clearSharedFiles, kSyncExtension, kSyncMimeType;
import 'local_addresses.dart';
import 'transfer_invite.dart';

/// The connection code and its prefixes are part of this transport, so a screen
/// that drives a transfer needs no second import for them.
export 'transfer_invite.dart';

// ── Size limits ───────────────────────────────────────────────────────────────

/// Largest sync payload this device will take from a peer, in bytes as they
/// travel.
///
/// A sync packet is a compressed binary record turned into base45 text, and a
/// player with a lifetime of throws behind them stays well under a megabyte.
/// The ceiling is not there to fit the honest case, it is there so a peer that
/// keeps sending cannot be answered forever.
const int kMaxSyncTransferBytes = 16 * 1024 * 1024;

/// Largest database a backup transfer will take, in bytes.
///
/// Higher than [kMaxSyncTransferBytes] because a backup is the SQLite file
/// itself rather than a compressed record of it, and it has to stay above any
/// database this app can plausibly produce. Still low enough that the file sits
/// in memory on the way to disk without putting the process at risk.
const int kMaxBackupTransferBytes = 128 * 1024 * 1024;

/// Raised when a peer sends, or claims to send, more than the transfer allows.
///
/// Only reachable after the pairing number has been approved, so it says
/// nothing about who the peer is; it caps what an approved one can spend of
/// this device's memory.
class SyncPayloadTooLargeException implements Exception {
  const SyncPayloadTooLargeException();

  @override
  String toString() => 'The other device sent more data than this app accepts';
}

// ── Transfer failures ─────────────────────────────────────────────────────────

/// Why a transfer could not be opened on this device.
enum TransferStartFailure {
  /// The device is on no network a peer could reach it over. Wi-Fi is off, or
  /// the only connection is mobile data.
  noLocalAddress,

  /// The socket could not be bound, twice in a row.
  bindFailed,
}

/// Raised when [SyncServer.start] cannot offer a transfer.
///
/// Typed rather than a bare exception because the two reasons need different
/// words on screen: one is fixed by turning Wi-Fi on, the other by restarting
/// the app. The start used to throw whatever came up, which the sync screen did
/// not catch at all, leaving its button spinning forever.
class TransferStartException implements Exception {
  const TransferStartException(this.reason);

  final TransferStartFailure reason;

  @override
  String toString() => 'The transfer could not be started: ${reason.name}';
}

/// Raised when no address in the invitation answered at all.
///
/// Distinct from a timeout on purpose. A timeout means the other device heard
/// this one and the user has not confirmed yet; this means nothing was heard,
/// which is what a guest network with client isolation looks like from here.
class TransferUnreachableException implements Exception {
  const TransferUnreachableException();

  @override
  String toString() => 'The other device could not be reached';
}

/// Raised when a scanned code has outlived [kInviteLifetime].
class TransferInviteExpiredException implements Exception {
  const TransferInviteExpiredException();

  @override
  String toString() => 'This connection code has expired';
}

// ── Sync range ────────────────────────────────────────────────────────────────

/// How far back a sync reaches when collecting a player's throws.
///
/// Only the individual throws are cut off by this. Everything older is folded
/// into the stats snapshot that travels with the packet, so the receiver's
/// lifetime numbers come out the same whichever range was picked.
enum SyncRange {
  day(1),
  week(7),
  month(30),
  all(null);

  const SyncRange(this.days);

  /// Days of history covered, or null for the player's whole history.
  final int? days;
}

// ── Sync throw ────────────────────────────────────────────────────────────────

/// A single throw in the wire format exchanged during device-to-device sync.
///
/// This is a transport-only mirror of [DartThrow] without DB ids; [thrownAt]
/// (ms since epoch) doubles as the deduplication key when merging on the
/// receiving device.
class SyncThrow {
  final int score;
  final int dartsUsed;
  final int remainingBefore;
  final int thrownAt; // ms since epoch: used as dedup key
  final bool bust;
  final int leg;
  final int set;

  /// How many darts of the visit were thrown at a finish, 0 to 3. Travels
  /// because the receiving device cannot work it out: the individual darts stay
  /// behind, and every imported throw lands in one hidden game whose check-out
  /// rule is not the one it was played under.
  final int checkoutDarts;

  const SyncThrow({
    required this.score,
    required this.dartsUsed,
    required this.remainingBefore,
    required this.thrownAt,
    required this.bust,
    required this.leg,
    required this.set,
    this.checkoutDarts = 0,
  });

  /// Builds a transport throw from a stored [DartThrow].
  factory SyncThrow.fromDartThrow(DartThrow t) => SyncThrow(
    score: t.score,
    dartsUsed: t.dartsUsed,
    remainingBefore: t.remainingBefore,
    thrownAt: t.thrownAt.millisecondsSinceEpoch,
    bust: t.bust,
    leg: t.leg,
    set: t.set,
    checkoutDarts: t.checkoutDarts,
  );

  /// Converts back to a storable [DartThrow] under the given game and player.
  DartThrow toDartThrow({required int gameId, required int playerId}) =>
      DartThrow(
        gameId: gameId,
        playerId: playerId,
        score: score,
        dartsUsed: dartsUsed,
        remainingBefore: remainingBefore,
        thrownAt: DateTime.fromMillisecondsSinceEpoch(thrownAt),
        bust: bust,
        leg: leg,
        set: set,
        checkoutDarts: checkoutDarts,
      );

  /// Serializes this throw to its JSON wire representation.
  Map<String, dynamic> toJson() => {
    'score': score,
    'darts_used': dartsUsed,
    'remaining_before': remainingBefore,
    'thrown_at': thrownAt,
    'bust': bust,
    'leg': leg,
    'set': set,
    'checkout_darts': checkoutDarts,
  };

  /// Parses a throw from JSON, tolerating bool-or-int `bust` encodings and
  /// rejecting out-of-range values to guard against corrupt or malicious data.
  factory SyncThrow.fromJson(Map<String, dynamic> j) {
    final score = j['score'] as int;
    final dartsUsed = j['darts_used'] as int;
    final remainingBefore = j['remaining_before'] as int;
    final thrownAt = j['thrown_at'] as int;
    // 'bust' may be serialised as bool OR as int 0/1 depending on platform
    final bust = j['bust'] == true || j['bust'] == 1;
    final leg = j['leg'] as int;
    final set = j['set'] as int;
    // Absent from packets an older app version wrote.
    final checkoutDarts = (j['checkout_darts'] as int? ?? 0).clamp(0, 3);

    // Bounds validation: reject obviously corrupt/malicious data
    if (score < 0 || score > 180) {
      throw FormatException('Invalid score: $score');
    }
    if (dartsUsed < 1 || dartsUsed > 3) {
      throw FormatException('Invalid dartsUsed: $dartsUsed');
    }
    if (remainingBefore < 0 || remainingBefore > 1001) {
      throw FormatException('Invalid remainingBefore: $remainingBefore');
    }
    if (leg < 1 || leg > 100) {
      throw FormatException('Invalid leg: $leg');
    }
    if (set < 1 || set > 100) {
      throw FormatException('Invalid set: $set');
    }

    return SyncThrow(
      score: score,
      dartsUsed: dartsUsed,
      remainingBefore: remainingBefore,
      thrownAt: thrownAt,
      bust: bust,
      leg: leg,
      set: set,
      checkoutDarts: checkoutDarts,
    );
  }
}

// ── Sync stats snapshot ───────────────────────────────────────────────────────

/// Aggregate per-player statistics carried alongside the throws in a sync,
/// so the receiver can display totals without recomputing from raw history.
class SyncStats {
  final int totalDarts;
  final int totalVisits;
  final double average;
  final int legsWon;
  final int highestVisit;
  final int busts;
  final int count180;

  const SyncStats({
    required this.totalDarts,
    required this.totalVisits,
    required this.average,
    required this.legsWon,
    required this.highestVisit,
    required this.busts,
    required this.count180,
  });

  /// Serializes these stats to their JSON wire representation.
  Map<String, dynamic> toJson() => {
    'total_darts': totalDarts,
    'total_visits': totalVisits,
    'average': average,
    'legs_won': legsWon,
    'highest_visit': highestVisit,
    'busts': busts,
    'count_180': count180,
  };

  /// Parses stats from JSON, defaulting any missing field to zero.
  factory SyncStats.fromJson(Map<String, dynamic> j) => SyncStats(
    totalDarts: j['total_darts'] as int? ?? 0,
    totalVisits: j['total_visits'] as int? ?? 0,
    average: (j['average'] as num?)?.toDouble() ?? 0,
    legsWon: j['legs_won'] as int? ?? 0,
    highestVisit: j['highest_visit'] as int? ?? 0,
    busts: j['busts'] as int? ?? 0,
    count180: j['count_180'] as int? ?? 0,
  );
}

// ── Sync origin ───────────────────────────────────────────────────────────────

/// The device id standing for data that arrived before devices were told
/// apart, whether it is stored locally or travelling in a packet.
///
/// It can never collide with a real [DeviceIdentity], which is always 16
/// characters long.
const String kLegacyOrigin = '';

/// One device's aggregated history as it travels in a packet.
///
/// A packet carries one of these per device it knows about, the sender
/// included. Keeping them apart is what lets a receiver drop its own
/// contribution back out: without it, data a device sent earlier comes home
/// folded into someone else's total and is counted twice.
class SyncOrigin {
  /// Which device the numbers were produced on, or [kLegacyOrigin].
  final String device;

  /// That device's stats snapshot, in the same shape as `local_stats_json`.
  final String snapshotJson;

  const SyncOrigin({required this.device, required this.snapshotJson});

  /// Serializes this origin to its JSON wire representation.
  Map<String, dynamic> toJson() => {'device': device, 'snapshot': snapshotJson};

  /// Parses an origin from JSON.
  factory SyncOrigin.fromJson(Map<String, dynamic> j) => SyncOrigin(
    device: j['device'] as String? ?? kLegacyOrigin,
    snapshotJson: j['snapshot'] as String? ?? '',
  );
}

// ── Sync packet ───────────────────────────────────────────────────────────────

/// The full payload transferred for one player during a sync: identity,
/// favorite doubles, aggregate [stats], the list of [throws], and an optional
/// full historical stats snapshot. [version] guards the wire format.
class SyncPacket {
  final int version;
  final String senderDevice;

  /// The sending device's [DeviceIdentity], or empty when the packet came from
  /// an app version that had none.
  final String senderDeviceId;

  final String playerUuid;
  final String playerName;
  final String favoriteDoubles;
  final SyncStats stats;
  final List<SyncThrow> throws;

  /// Every device's snapshot separately, the sender's included.
  ///
  /// Empty in packets from before devices were told apart; [localStatsJson] is
  /// then the only snapshot there is.
  final List<SyncOrigin> origins;

  /// Which device produced each entry of [throws], in the same order.
  ///
  /// Empty when the packet does not say, which means the sender is the only
  /// device the throws can be attributed to. A device passing on what it
  /// received keeps the original attribution here, so the data can find its
  /// way home without arriving as the passing device's own.
  final List<String> throwOrigins;

  // Full historical stats snapshot (local_stats_json): includes data from cleared game history.
  //
  // Everything in [origins] added together. Kept because an app version that
  // does not know about origins reads this field and nothing else; a receiver
  // that does know ignores it in favour of the breakdown.
  final String? localStatsJson;

  /// How far back [throws] reaches, in days, or null when it holds every throw.
  ///
  /// Only the individual throws are cut off by this; the throws left out were
  /// folded into [localStatsJson] before sending, so no aggregate number is
  /// lost by picking a shorter range.
  final int? rangeDays;

  const SyncPacket({
    required this.version,
    required this.senderDevice,
    required this.playerUuid,
    required this.playerName,
    required this.favoriteDoubles,
    required this.stats,
    required this.throws,
    this.senderDeviceId = '',
    this.origins = const [],
    this.throwOrigins = const [],
    this.localStatsJson,
    this.rangeDays,
  });

  /// Which device the throw at [index] was played on, falling back to the
  /// sender for a packet that does not attribute its throws.
  String originOfThrow(int index) =>
      index < throwOrigins.length ? throwOrigins[index] : senderDeviceId;

  /// Serializes this packet to its JSON wire representation.
  Map<String, dynamic> toJson() => {
    'version': version,
    'sender_device': senderDevice,
    if (senderDeviceId.isNotEmpty) 'sender_device_id': senderDeviceId,
    'player_uuid': playerUuid,
    'player_name': playerName,
    'favorite_doubles': favoriteDoubles,
    'stats': stats.toJson(),
    'throws': throws.map((t) => t.toJson()).toList(),
    if (origins.isNotEmpty) 'origins': origins.map((o) => o.toJson()).toList(),
    if (throwOrigins.isNotEmpty) 'throw_origins': throwOrigins,
    if (localStatsJson != null) 'local_stats_json': localStatsJson,
    if (rangeDays != null) 'range_days': rangeDays,
  };

  /// Parses a packet from JSON, applying defaults for optional fields.
  factory SyncPacket.fromJson(Map<String, dynamic> j) => SyncPacket(
    version: j['version'] as int,
    senderDevice: j['sender_device'] as String? ?? 'Unknown',
    senderDeviceId: j['sender_device_id'] as String? ?? '',
    playerUuid: j['player_uuid'] as String,
    playerName: j['player_name'] as String,
    favoriteDoubles: j['favorite_doubles'] as String? ?? '',
    stats: SyncStats.fromJson(j['stats'] as Map<String, dynamic>? ?? {}),
    throws: (j['throws'] as List? ?? [])
        .map((t) => SyncThrow.fromJson(t as Map<String, dynamic>))
        .toList(),
    origins: (j['origins'] as List? ?? [])
        .map((o) => SyncOrigin.fromJson(o as Map<String, dynamic>))
        .toList(),
    throwOrigins: (j['throw_origins'] as List? ?? [])
        .map((o) => o as String)
        .toList(),
    localStatsJson: j['local_stats_json'] as String?,
    rangeDays: j['range_days'] as int?,
  );

  /// A copy of this packet under a different [playerName], used when the
  /// receiver resolves a name clash by importing under an alternative name.
  SyncPacket withName(String name) => SyncPacket(
    version: version,
    senderDevice: senderDevice,
    senderDeviceId: senderDeviceId,
    playerUuid: playerUuid,
    playerName: name,
    favoriteDoubles: favoriteDoubles,
    stats: stats,
    throws: throws,
    origins: origins,
    throwOrigins: throwOrigins,
    localStatsJson: localStatsJson,
    rangeDays: rangeDays,
  );
}

// ── Server ────────────────────────────────────────────────────────────────────

/// How far a Wi-Fi transfer has got, from the sender's side.
enum SyncServerState {
  /// Bound and listening, nobody has asked yet.
  waiting,

  /// A peer with the right token is asking to be let in.
  pending,

  /// The user approved, the payload goes out on the next request.
  approved,

  /// The payload has been handed over, and the peer's own is now awaited.
  served,

  /// The peer has answered with its side of the exchange. Whether that answer
  /// carried anything is [SyncServer.returnedPayload].
  returned,

  /// The user turned the peer away.
  rejected,
}

/// Hosts a one-shot local HTTP server that exchanges a payload with one peer
/// over the local network, once the user has confirmed the peer is the right
/// one.
///
/// A peer needs the token from the connection QR to get any answer at all,
/// which is what keeps the payload from anyone else who happens to be on the
/// same Wi-Fi. Past that door it still waits: the first request only starts a
/// pairing, both devices show the same four digits, and the payload is released
/// when the user approves it here.
///
/// The exchange goes both ways in one pairing. After the payload has gone out
/// the server stays up briefly for the peer to post its own side back, which is
/// what makes two devices reconcile in one confirmation instead of two runs
/// with the roles swapped. The peer always answers, with an empty body when it
/// has nothing to give, so the wait ends on an answer rather than on the
/// timeout. Then the server stops rather than staying open for the rest of the
/// session.
class SyncServer {
  /// How long to wait for the peer's side after the payload has gone out. Only
  /// reached when the peer disappears mid-exchange; an ordinary run answers at
  /// once.
  static const Duration returnTimeout = Duration(seconds: 90);

  /// Set on a one-way payload response, telling the peer to say when it has
  /// the whole thing.
  ///
  /// A two-way exchange needs no such thing: the peer's own packet coming back
  /// is the confirmation, which is exactly why the profile sync survived over a
  /// raised network and the database transfer did not.
  static const String confirmHeader = 'x-transfer-confirm';

  /// How long a one-way transfer waits for the peer to confirm before calling
  /// it done anyway.
  ///
  /// The peer sends this the moment the last byte is in, so the wait is short
  /// in every ordinary run. Only a peer that vanished mid-body reaches the end
  /// of it, and then finishing is the right answer: the payload is out and
  /// there is nothing left to hold the session open for.
  @visibleForTesting
  static Duration confirmationTimeout = const Duration(seconds: 30);

  /// How much of the payload goes out before the progress is reported again.
  ///
  /// The whole body used to be handed to the socket in one call, which is fine
  /// for a sync packet and useless for a database: the user would watch a still
  /// screen for as long as it takes. Small enough to move a bar, large enough
  /// that the flush per slice costs nothing next to the write.
  static const int _kChunkBytes = 64 * 1024;

  HttpServer? _server;

  /// Raised while [start] is in flight.
  ///
  /// Two starts overlapping is how a session ended up with two sockets, one of
  /// them unreachable and neither of them stopped. The screens guard their
  /// buttons, but a lifecycle change can call in beside a tap.
  bool _starting = false;

  List<int>? _payload;
  ContentType _contentType = ContentType.text;
  bool _twoWay = true;
  String? _returned;

  /// Completed when a one-way peer reports it has the whole payload.
  Completer<void>? _confirmation;

  Timer? _returnTimer;
  String _token = '';
  String _pin = '';

  final ValueNotifier<double> _progress = ValueNotifier(0);

  /// How much of the payload has gone out, from 0 to 1. Stays at 0 until a peer
  /// is actually being served.
  ValueListenable<double> get progress => _progress;

  /// What the peer sent back, or null when it had nothing for this device.
  /// Only meaningful once the state is [SyncServerState.returned].
  String? get returnedPayload =>
      _returned == null || _returned!.isEmpty ? null : _returned;

  final ValueNotifier<SyncServerState> _state = ValueNotifier(
    SyncServerState.waiting,
  );

  /// Follows the transfer for the sender's screen.
  ValueListenable<SyncServerState> get state => _state;

  /// The four digits both devices show while the transfer is being confirmed.
  String get pin => _pin;

  /// Whether the server is currently bound and listening.
  bool get isRunning => _server != null;

  /// Binds the server on a free port, ready to serve [payload], and returns the
  /// invitation a peer needs to reach it.
  ///
  /// [twoWay] is what a profile sync wants: the peer answers with its own side
  /// and one pairing settles both devices. Handing a whole database over is not
  /// like that, it replaces the receiver, so there is nothing to hand back and
  /// the session ends as soon as the payload is out.
  ///
  /// [hotspot] is filled when this device raised the network the peer is meant
  /// to join, so a single code both joins it and names the endpoint on it.
  ///
  /// Throws [TransferStartException] rather than whatever the socket layer came
  /// up with, and looks for an address before it binds anything: a device with
  /// no local address has nothing to offer, and finding that out after a socket
  /// exists only leaves one to clean up.
  Future<TransferInvite> start(
    List<int> payload, {
    bool twoWay = true,
    ContentType? contentType,
    HotspotCredentials? hotspot,
    @visibleForTesting List<String>? addresses,
  }) async {
    if (_starting)
      throw const TransferStartException(TransferStartFailure.bindFailed);
    _starting = true;
    try {
      final reachableOn = addresses ?? await localTransferAddresses();
      if (reachableOn.isEmpty) {
        throw const TransferStartException(TransferStartFailure.noLocalAddress);
      }

      final random = Random.secure();

      _payload = payload;
      _contentType = contentType ?? ContentType.text;
      _twoWay = twoWay;
      _returned = null;
      _progress.value = 0;
      _token = List.generate(
        16,
        (_) => _kTokenAlphabet[random.nextInt(_kTokenAlphabet.length)],
      ).join();
      _pin = random.nextInt(10000).toString().padLeft(4, '0');
      _state.value = SyncServerState.waiting;

      _server = await _bind();
      _server!.listen(
        (req) => _handle(req).catchError((_) {}),
        onError: (_) {},
        cancelOnError: false,
      );

      return TransferInvite.forNow(
        addresses: reachableOn,
        port: _server!.port,
        token: _token,
        hotspot: hotspot,
      );
    } finally {
      _starting = false;
    }
  }

  /// Binds a listening socket on a port the system picks, with one retry.
  ///
  /// A port of 0 should never collide, but a socket the previous session left
  /// half closed can still refuse the bind for as long as it lingers. One short
  /// wait clears that; a second failure is real.
  Future<HttpServer> _bind() async {
    try {
      return await HttpServer.bind(InternetAddress.anyIPv4, 0);
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        return await HttpServer.bind(InternetAddress.anyIPv4, 0);
      } catch (_) {
        throw const TransferStartException(TransferStartFailure.bindFailed);
      }
    }
  }

  /// Releases the payload to the waiting peer.
  void approve() {
    if (_state.value == SyncServerState.pending) {
      _state.value = SyncServerState.approved;
    }
  }

  /// Turns the waiting peer away.
  void reject() {
    if (_state.value == SyncServerState.pending) {
      _state.value = SyncServerState.rejected;
    }
  }

  /// Answers one request according to how far the pairing has got.
  ///
  /// The peer polls rather than holding the connection open, which keeps a
  /// request from timing out while the user is still looking at their screen.
  Future<void> _handle(HttpRequest req) async {
    final response = req.response..headers.contentType = ContentType.json;

    // Anything without the token gets nothing, and does not disturb the user.
    if (req.uri.path != '/$_token') {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }

    if (req.method == 'POST') {
      await _handleReturn(req, response);
      return;
    }

    if (_state.value == SyncServerState.waiting) {
      _state.value = SyncServerState.pending;
    }

    switch (_state.value) {
      case SyncServerState.rejected:
        response.statusCode = HttpStatus.forbidden;
        await response.close();
      case SyncServerState.approved:
      case SyncServerState.served:
        final payload = _payload!;
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = _contentType
          ..headers.contentLength = payload.length
          ..headers.set(HttpHeaders.connectionHeader, 'close');
        if (!_twoWay) response.headers.set(confirmHeader, '1');

        // Written in slices so the sending screen has something to show. A
        // database takes long enough that one write and a still screen look
        // like a transfer that died.
        for (var start = 0; start < payload.length; start += _kChunkBytes) {
          final end = min(start + _kChunkBytes, payload.length);
          response.add(payload.sublist(start, end));
          await response.flush();
          _progress.value = end / payload.length;
        }

        // The state has to wait for the last byte. Announcing the hand-over
        // any earlier lets the screen shut the server down mid-response, and
        // a payload of a few tens of kilobytes, or a whole database, is still
        // in flight at that point, so the receiver sees the connection break
        // instead.
        await response.close();
        _progress.value = 1;

        // And the last byte written is still not the last byte received.
        // `close` hands the payload to the kernel; the peer may have most of a
        // database still to pull out of the buffers. Announcing the hand-over
        // there is what let the sending screen stop the server and, worse, take
        // the raised network down with it, leaving the receiver stuck at part
        // of the file with no error to show for it. So a one-way transfer waits
        // to be told, and a two-way one is told by the peer's own packet.
        if (!_twoWay) await _awaitConfirmation();

        if (_state.value != SyncServerState.served) {
          _state.value = SyncServerState.served;
          if (_twoWay) _startReturnTimer();
        }
      case SyncServerState.returned:
        // The exchange is over. Nothing is served twice.
        response.statusCode = HttpStatus.gone;
        await response.close();
      case SyncServerState.waiting:
      case SyncServerState.pending:
        response
          ..statusCode = HttpStatus.accepted
          ..write(jsonEncode({'pin': _pin}));
        await response.close();
    }
  }

  /// Waits for the peer to report that it holds the whole payload.
  ///
  /// Gives up after [confirmationTimeout] rather than never, because a peer
  /// that disappeared mid-body would otherwise leave the sending screen unable
  /// to start anything else.
  Future<void> _awaitConfirmation() async {
    final confirmation = Completer<void>();
    _confirmation = confirmation;
    try {
      await confirmation.future.timeout(confirmationTimeout);
    } catch (_) {
      // The peer never answered. The payload is out either way.
    } finally {
      _confirmation = null;
    }
  }

  /// Takes the peer's side of the exchange.
  ///
  /// Only once this device's own payload is out: before that there is no
  /// approved peer, and taking a packet from an unconfirmed one would let
  /// anyone holding the token push data in. An empty body is a valid answer and
  /// means the peer had nothing to send.
  ///
  /// The body is weighed as it arrives and refused past
  /// [kMaxSyncTransferBytes]. The peer is approved by then, but approving a
  /// pairing is not the same as handing it this device's memory, and the return
  /// leg is the one direction where the data comes in unasked.
  Future<void> _handleReturn(HttpRequest req, HttpResponse response) async {
    // A one-way transfer takes no packet back, only the word that the payload
    // arrived whole.
    if (!_twoWay) {
      final confirmation = _confirmation;
      if (confirmation == null || confirmation.isCompleted) {
        response.statusCode = HttpStatus.conflict;
      } else {
        await req.drain<void>();
        confirmation.complete();
        response.statusCode = HttpStatus.ok;
      }
      await response.close();
      return;
    }

    if (_state.value != SyncServerState.served) {
      response.statusCode = HttpStatus.conflict;
      await response.close();
      return;
    }

    final buffer = BytesBuilder(copy: false);
    try {
      await for (final chunk in req) {
        if (buffer.length + chunk.length > kMaxSyncTransferBytes) {
          throw const SyncPayloadTooLargeException();
        }
        buffer.add(chunk);
      }
    } on SyncPayloadTooLargeException {
      // The state stays at `served`, so the return timer still ends the wait
      // and the transfer this device already handed over keeps standing. Only
      // the direction back is lost, which is the same outcome as a peer that
      // never answered.
      response.statusCode = HttpStatus.requestEntityTooLarge;
      await response.close();
      return;
    }

    final body = utf8.decode(buffer.takeBytes());
    _returned = body;

    response.statusCode = HttpStatus.ok;

    // Same reason as the payload above, the other way round: the screen reacts
    // to `returned` by shutting the server down, so the answer has to be fully
    // written before the state says so, or the peer never sees it.
    await response.close();
    _returnTimer?.cancel();
    _state.value = SyncServerState.returned;
  }

  /// Gives up waiting for the peer's side after [returnTimeout], so a peer that
  /// vanished mid-exchange does not leave the sender's screen waiting forever.
  void _startReturnTimer() {
    _returnTimer?.cancel();
    _returnTimer = Timer(returnTimeout, () {
      if (_state.value == SyncServerState.served) {
        _returned = null;
        _state.value = SyncServerState.returned;
      }
    });
  }

  /// Stops the server and clears the payload and the session secrets.
  ///
  /// The state is deliberately left where it was. A screen shutting down calls
  /// this and then [dispose] without waiting, so a write here would land on a
  /// notifier that is already gone; [start] resets the state anyway.
  Future<void> stop() async {
    _returnTimer?.cancel();
    _returnTimer = null;

    final server = _server;
    _server = null;
    if (server != null) {
      // Gracefully first, and this is load bearing. A payload the size of a
      // database is still sitting in the socket buffers when the write loop
      // ends: `close()` on the response hands the bytes to the kernel, it does
      // not wait for the peer to read them. Forcing the socket down at that
      // moment tears the transfer out from under a receiver that is still
      // pulling it in, which is why one stopped at 39 percent while the sender
      // reported success. A graceful close waits for the connection to finish,
      // and only a peer that has stopped reading altogether reaches the force
      // below.
      try {
        await server.close().timeout(drainGrace);
      } catch (_) {
        await server.close(force: true);
      }
    }

    _confirmation = null;
    _payload = null;
    _token = '';
    _pin = '';
  }

  /// How long a stop waits for a peer to finish reading before forcing the
  /// socket down.
  ///
  /// Only ever reached by a peer that stopped reading: an ordinary transfer has
  /// nothing left but what the buffers hold, which drains in a moment.
  @visibleForTesting
  static Duration drainGrace = const Duration(seconds: 45);

  /// Releases the notifiers. Call when the owning screen goes away.
  void dispose() {
    _returnTimer?.cancel();
    _state.dispose();
    _progress.dispose();
  }

  /// Characters a session token is built from: unambiguous, and all inside the
  /// QR alphanumeric set so the connection code stays dense.
  static const _kTokenAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
}

// ── Sharing a profile as a file ───────────────────────────────────────────────

/// Hands one player's history to the share sheet as a file.
///
/// The one way two iPhones exchange a profile with no network between them at
/// all: Apple lets no app raise one, so AirDrop through the share sheet is what
/// is left. It carries the same text a QR code would, so the receiving side
/// decodes it with `decodeSyncPayload` and nothing new had to be understood.
///
/// One direction only, like a code on a screen. The return leg belongs to the
/// Wi-Fi transfer and stays there.
///
/// [origin] anchors the sheet on an iPad, where a popover without one fails
/// instead of opening. Returns whether the sheet was used rather than
/// dismissed.
Future<bool> shareSyncFile(
  String payload, {
  required String playerName,
  Rect? origin,
}) async {
  final dir = await getTemporaryDirectory();

  // Whatever an earlier share left, cleared before the next one is written
  // rather than after the sheet closes. A target may still be reading the file
  // off its content URI at that point, and deleting it there is how a share
  // that looked finished arrives empty.
  await clearSharedFiles(dir, kSyncExtension);

  final file = File('${dir.path}/${syncFileName(playerName, DateTime.now())}');
  await file.writeAsString(payload, flush: true);

  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: kSyncMimeType)],
      sharePositionOrigin: origin,
    ),
  );
  return result.status == ShareResultStatus.success;
}

/// Name a shared profile is offered under.
///
/// Carries the player so a receiver can see whose history arrived before
/// opening it, and the date so two of them stay apart.
String syncFileName(String playerName, DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  final safe = playerName
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final who = safe.isEmpty ? 'player' : safe.toLowerCase();
  return '$who-${now.year}-${two(now.month)}-${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}.$kSyncExtension';
}

// ── Client ────────────────────────────────────────────────────────────────────

/// Raised when the sending device turned the transfer down.
class SyncRejectedException implements Exception {
  const SyncRejectedException();

  @override
  String toString() => 'The other device declined the transfer';
}

/// Fetches a payload from a peer's [SyncServer] over the local network.
///
/// An invitation names several addresses, because the sending device cannot
/// know which of its own the peer shares a network with. The client tries them
/// in turn and keeps the first that answers; everything after that runs against
/// that one address alone. Reuse one instance for the fetch and the return
/// post, so the answer goes back the way it came.
class SyncClient {
  /// How long to keep asking before giving up on the user confirming.
  static const _kTimeout = Duration(minutes: 2);

  /// How long to wait between asking again.
  static const _kPollInterval = Duration(milliseconds: 600);

  /// How long to keep trying addresses that answer nothing at all before
  /// calling the peer unreachable.
  ///
  /// Well short of [_kTimeout]: that one covers a user who has not confirmed
  /// yet, and there is no point holding a receiver on a spinner for two minutes
  /// when nothing on the far side has ever replied.
  static const _kUnreachableAfter = Duration(seconds: 15);

  /// The same, for a transfer whose peer raised the network this device has
  /// just joined.
  ///
  /// Longer because the interface came up seconds ago: the address is still
  /// being handed out, the route is still settling, and the first requests go
  /// out into a network that is not quite there yet. Calling that unreachable
  /// is calling it too early.
  static const _kUnreachableAfterJoin = Duration(seconds: 40);

  /// How long an address gets to answer while none of them has yet.
  ///
  /// Short, because it is spent once per candidate on every round until one
  /// answers, and a peer on the same network answers in milliseconds.
  static const _kProbeTimeout = Duration(seconds: 4);

  /// How long the chosen address gets, once one has answered.
  ///
  /// The probe timeout must not apply here. There is nothing left to try, so
  /// cutting a slow answer short only starts the search again and, worse, does
  /// it against a server that has already seen the request: that is how a
  /// receiver gave up while the sender was showing its pairing dialog.
  static const _kRequestTimeout = Duration(seconds: 15);

  /// How long the body may go quiet before the transfer is given up on.
  ///
  /// A network that disappears breaks no connection, it goes silent: the peer
  /// took its raised hotspot down, or walked out of range. Without this the
  /// read simply never returns and the receiving screen sits at whatever
  /// percentage it had reached, with nothing to show the user.
  static const _kBodyStallTimeout = Duration(seconds: 20);

  /// Ceiling for an answer that is not the payload. The pairing number and the
  /// refusals are a line of JSON; nothing that is not the payload is large.
  static const _kMaxStatusBytes = 64 * 1024;

  /// The address that answered, once one has. Null until then.
  ///
  /// The address alone, not the URL: the token comes from the invitation on
  /// every call, so a later call cannot ride on a token an earlier one carried.
  String? _reached;

  /// The text payload of a profile sync. See [fetchBytes], which this decodes.
  ///
  /// Takes the sync ceiling rather than the backup one: this end of the wire
  /// only ever carries a packet, and letting it take a database sized body
  /// would leave the tighter limit unused on the one path that can hold it.
  Future<String> fetch(
    TransferInvite invite, {
    void Function(String pin)? onPin,
  }) async => utf8.decode(
    await fetchBytes(invite, onPin: onPin, maxBytes: kMaxSyncTransferBytes),
  );

  /// Connects to [invite] and returns the payload once the sending device has
  /// approved the transfer.
  ///
  /// [onPin] is called with the four digits as soon as the server names them,
  /// so the receiver can show the user what to compare against. [onProgress]
  /// reports the bytes arrived and the total expected, which is what a database
  /// transfer needs: it is large enough that a screen without a bar looks
  /// stuck. The total is 0 when the sender announced no length.
  ///
  /// [maxBytes] is what the body may weigh before the transfer is abandoned.
  /// Throws [SyncPayloadTooLargeException] on an announced length above it and
  /// again on the bytes actually arriving, because a peer is free to announce
  /// one length and send another.
  ///
  /// Throws [TransferInviteExpiredException] on a code that has outlived its
  /// session, and [TransferUnreachableException] when no address ever answered.
  Future<List<int>> fetchBytes(
    TransferInvite invite, {
    void Function(String pin)? onPin,
    void Function(int received, int total)? onProgress,
    int maxBytes = kMaxBackupTransferBytes,
  }) async {
    if (invite.isExpired) throw const TransferInviteExpiredException();

    final client = HttpClient()
      ..connectionTimeout = _kProbeTimeout
      ..idleTimeout = const Duration(seconds: 10);

    final started = DateTime.now();
    final deadline = started.add(_kTimeout);
    final unreachableAfter = invite.hotspot != null
        ? _kUnreachableAfterJoin
        : _kUnreachableAfter;
    var announced = false;

    try {
      while (true) {
        final res = await _get(client, invite);

        if (res == null) {
          // Nothing on any of the addresses answered this round.
          if (DateTime.now().difference(started) > unreachableAfter) {
            throw const TransferUnreachableException();
          }
          await Future<void>.delayed(_kPollInterval);
          continue;
        }

        final total = res.contentLength < 0 ? 0 : res.contentLength;

        // Everything that is not the payload is a short status answer, and
        // holding those to the payload's ceiling would leave a peer free to
        // spend it on a reply that should be a few dozen bytes.
        final limit = res.statusCode == HttpStatus.ok
            ? maxBytes
            : _kMaxStatusBytes;
        if (total > limit) throw const SyncPayloadTooLargeException();

        // Collected as bytes, because the payload may be a database rather
        // than text. Only the small status answers below are ever decoded.
        // A `BytesBuilder` rather than a plain `List<int>`: a growable int list
        // holds a machine word per byte, so a database sized body would cost
        // eight times its own length before the ceiling ever came into it.
        final body = BytesBuilder(copy: false);
        try {
          await for (final chunk in res.timeout(_kBodyStallTimeout)) {
            if (body.length + chunk.length > limit) {
              throw const SyncPayloadTooLargeException();
            }
            body.add(chunk);
            if (res.statusCode == HttpStatus.ok) {
              onProgress?.call(body.length, total);
            }
          }
        } on TimeoutException {
          // Not the timeout the poll loop means, which is a user who has not
          // confirmed. This one is the far side gone quiet mid-body, and it has
          // to say so rather than leave the screen counting.
          throw const TransferUnreachableException();
        }

        switch (res.statusCode) {
          case HttpStatus.ok:
            // The sender is holding the session open until it hears this, and
            // on a transfer over a network the sender raised it is holding the
            // network up too. Said before anything is written to disk, because
            // the wait on the other side is measured against a peer that
            // vanished, not against a peer that is busy.
            if (res.headers.value(SyncServer.confirmHeader) == '1') {
              await _confirmDelivery(invite);
            }
            return body.takeBytes();
          case HttpStatus.forbidden:
            throw const SyncRejectedException();
          case HttpStatus.accepted:
            if (!announced) {
              final pin =
                  (jsonDecode(utf8.decode(body.takeBytes()))
                      as Map<String, dynamic>)['pin'];
              if (pin is String) {
                announced = true;
                onPin?.call(pin);
              }
            }
          default:
            throw Exception('Server responded with ${res.statusCode}');
        }

        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('The transfer was not confirmed in time');
        }
        await Future<void>.delayed(_kPollInterval);
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Asks one round of the invitation's addresses, returning the first answer,
  /// or null when none of them answered.
  ///
  /// Once an address has answered it is the only one asked again. Switching
  /// later would risk a second request reaching an approved server and taking
  /// the payload a second time; while nothing has answered, the server is still
  /// in `waiting` and a probe costs it nothing.
  Future<HttpClientResponse?> _get(
    HttpClient client,
    TransferInvite invite,
  ) async {
    final chosen = _reached;
    final timeout = chosen == null ? _kProbeTimeout : _kRequestTimeout;

    for (final address in chosen != null ? [chosen] : invite.addresses) {
      try {
        final res = await (await client.getUrl(
          invite.endpointAt(address),
        )).close().timeout(timeout);
        _reached = address;
        return res;
      } catch (_) {
        // This address is not the one. The next is tried, and if none is, the
        // caller decides whether that has gone on long enough to give up.
        continue;
      }
    }
    return null;
  }

  /// Tells the sender the payload arrived whole.
  ///
  /// Best effort and never fatal: what came in is already in hand, and a sender
  /// that does not hear this finishes on its own timeout instead. The point is
  /// that it usually does hear it, so it stops the moment the transfer is over
  /// rather than in the middle of one.
  Future<void> _confirmDelivery(TransferInvite invite) async {
    final address = _reached;
    if (address == null) return;

    final client = HttpClient()
      ..connectionTimeout = _kProbeTimeout
      ..idleTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(invite.endpointAt(address));
      request.headers.contentType = ContentType.text;
      final res = await request.close().timeout(_kRequestTimeout);
      await res.drain<void>();
    } catch (_) {
      // The sender falls back on its own wait.
    } finally {
      client.close(force: true);
    }
  }

  /// Sends this device's own side of the exchange back to [invite].
  ///
  /// Always called after a successful [fetch], with an empty [payload] when
  /// there is nothing to return: the sender is waiting on an answer either way,
  /// and an empty one ends its wait immediately instead of after the timeout.
  ///
  /// A failure here is deliberately not fatal to the caller. The data this
  /// device received is already stored, and the only thing lost is the other
  /// direction, which the user can run again.
  Future<void> post(TransferInvite invite, String payload) async {
    final client = HttpClient()
      ..connectionTimeout = _kProbeTimeout
      ..idleTimeout = const Duration(seconds: 10);

    try {
      // The address the payload came in on, when there is one. A fetch on this
      // same client has already found the one that works, and trying the others
      // again would only spend the peer's waiting time.
      for (final address in _reached != null ? [_reached!] : invite.addresses) {
        final HttpClientResponse res;
        try {
          final request = await client.postUrl(invite.endpointAt(address));
          request.headers.contentType = ContentType.text;
          request.write(payload);
          res = await request.close().timeout(const Duration(seconds: 30));
        } catch (_) {
          continue;
        }

        await res.drain<void>();
        if (res.statusCode != HttpStatus.ok) {
          throw Exception('Server responded with ${res.statusCode}');
        }
        return;
      }
      throw const TransferUnreachableException();
    } finally {
      client.close(force: true);
    }
  }
}
