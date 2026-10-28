import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/players_provider.dart';
import '../database/db_helper.dart';
import '../models/dart_throw.dart';
import '../models/player.dart';
import '../services/device_description.dart';
import '../services/device_identity.dart';
import '../services/local_hotspot.dart';
import '../services/sync_codec.dart';
import '../services/sync_service.dart';
import '../utils/layout.dart';
import '../widgets/wifi_pairing.dart';

/// How to resolve a name clash when importing a synced player: reuse the
/// existing local player.
enum _NameResolution { useExisting }

/// The localized label for a range given in days, with null meaning the
/// player's whole history. Shared by the sender's picker and the receiver's
/// confirmation dialog, which only ever sees the day count.
String _rangeLabelForDays(AppLocalizations l, int? days) => switch (days) {
  1 => l.syncRangeDay,
  7 => l.syncRangeWeek,
  30 => l.syncRangeMonth,
  _ => l.syncRangeAll,
};

/// Builds a [SyncPacket] for [player] covering [range], out of the live throws
/// plus every stats snapshot the player carries: this device's own, covering
/// its cleared game history, and one per device that ever synced to it.
///
/// The aggregate stats always describe the player's whole history, whatever
/// [range] is: the throws it leaves out are folded into the snapshot that
/// travels along, so a short range costs individual throws and nothing else.
///
/// Which snapshot they are folded into is what keeps a sync correct in both
/// directions. A throw played here folds into this device's snapshot, a throw
/// that arrived from another device folds back into that device's own, and the
/// receiver drops whichever snapshot carries its own id. Fold everything into
/// one total instead and a device gets its own history handed back as part of
/// somebody else's, on top of the throws it already has.
Future<SyncPacket> buildSyncPacket(
  Player player,
  String senderDevice,
  SyncRange range,
) async {
  final db = DbHelper.instance;
  final deviceId = await DeviceIdentity.id;

  final byOrigin = await db.getThrowsForPlayerByOrigin(player.id!);
  final allThrows = [for (final throws in byOrigin.values) ...throws]
    ..sort((a, b) => a.thrownAt.compareTo(b.thrownAt));

  // Live stats
  int liveDarts = 0, liveScored = 0, liveLegs = 0, liveHigh = 0;
  int liveBusts = 0, live180 = 0;
  for (final t in allThrows) {
    liveDarts += t.dartsUsed;
    if (!t.bust) {
      liveScored += t.score;
      if (t.score > liveHigh) liveHigh = t.score;
      if (t.score == 180) live180++;
      if (t.remainingBefore - t.score == 0) liveLegs++;
    } else {
      liveBusts++;
    }
  }

  // Persistent stats from every snapshot at once: what the sending device
  // cleared away itself, and what other devices contributed.
  final combined = await db.combinedSnapshotJson(player.id!);

  int persD = 0,
      persV = 0,
      persLegs = 0,
      persHigh = 0,
      persBusts = 0,
      pers180 = 0,
      persScored = 0;
  if (combined != null && combined.isNotEmpty) {
    try {
      final p = jsonDecode(combined) as Map<String, dynamic>;
      persD = p['total_darts'] as int? ?? 0;
      persV = p['total_visits'] as int? ?? 0;
      persLegs = p['legs_won'] as int? ?? 0;
      persHigh = p['highest_visit'] as int? ?? 0;
      persBusts = p['busts'] as int? ?? 0;
      pers180 = p['count_180'] as int? ?? 0;
      persScored = p['total_scored'] as int? ?? 0;
    } catch (_) {}
  }

  final totalDarts = liveDarts + persD;
  final totalVisits = allThrows.length + persV;
  final totalScored = liveScored + persScored;
  final totalLegs = liveLegs + persLegs;
  final highestVisit = liveHigh > persHigh ? liveHigh : persHigh;
  final totalBusts = liveBusts + persBusts;
  final total180 = live180 + pers180;
  final avg = totalDarts == 0 ? 0.0 : (totalScored / totalDarts) * 3;

  // Split the history at the range's cutoff. What falls outside still has to
  // reach the other device, just as aggregated numbers instead of throws.
  final cutoff = range.days == null
      ? null
      : DateTime.now()
            .subtract(Duration(days: range.days!))
            .millisecondsSinceEpoch;

  /// Splits one device's throws into what travels as throws and what gets
  /// folded into that device's snapshot.
  (List<DartThrow>, List<DartThrow>) split(List<DartThrow> throws) {
    final included = <DartThrow>[];
    final excluded = <DartThrow>[];
    for (final t in throws) {
      if (cutoff == null || t.thrownAt.millisecondsSinceEpoch >= cutoff) {
        included.add(t);
      } else {
        excluded.add(t);
      }
    }
    return (included, excluded);
  }

  /// The same split for throws played on this device, but along whole games:
  /// a game is inside the range when its last throw is.
  ///
  /// Half a game has no perfect leg and no average worth the name, and a game
  /// cut down the middle would have both halves claim it, once as a game
  /// folded into the snapshot and once as a game travelling as throws.
  (List<DartThrow>, List<DartThrow>) splitByGame(List<DartThrow> throws) {
    if (cutoff == null) return (throws, const []);

    final lastThrowOfGame = <int, int>{};
    for (final t in throws) {
      final at = t.thrownAt.millisecondsSinceEpoch;
      if (at > (lastThrowOfGame[t.gameId] ?? 0)) lastThrowOfGame[t.gameId] = at;
    }

    final included = <DartThrow>[];
    final excluded = <DartThrow>[];
    for (final t in throws) {
      (lastThrowOfGame[t.gameId]! >= cutoff ? included : excluded).add(t);
    }
    return (included, excluded);
  }

  final stored = await db.getOriginSnapshots(player.id!);
  final snapshots = <String, String>{};
  final travelling = <(String, DartThrow)>[];

  // This device's own throws and its own snapshot. The throws left out travel
  // as aggregated stats; the ones travelling as throws still need everything
  // their game knows about itself folded in, because a synced throw arrives
  // without its game.
  final (includedOwn, excludedOwn) = splitByGame(byOrigin[null] ?? const []);
  travelling.addAll(includedOwn.map((t) => (deviceId, t)));

  final ownSnapshot = await db.addTravellingGameFacts(
    await db.foldThrowsIntoSnapshot(player.localStatsJson, excludedOwn),
    includedOwn,
  );
  snapshots[deviceId] = ownSnapshot == null ? '' : jsonEncode(ownSnapshot);

  // Everything that arrived from somewhere else is passed on under the device
  // it was played on, throws and snapshot alike.
  for (final entry in byOrigin.entries) {
    final origin = entry.key;
    if (origin == null || origin == kLegacyOrigin) continue;

    final (included, excluded) = split(entry.value);
    travelling.addAll(included.map((t) => (origin, t)));

    // What these games knew about themselves is already part of the snapshot
    // their device sent, so only the plain counters are folded here.
    final snapshot = await db.foldThrowsIntoSnapshot(
      stored[origin],
      excluded,
      gameFacts: false,
    );
    snapshots[origin] = snapshot == null ? '' : jsonEncode(snapshot);
  }

  // Devices that are only aggregates here, because a shorter range on the
  // device that passed them on left no throws of theirs behind.
  for (final entry in stored.entries) {
    if (entry.key == kLegacyOrigin) continue;
    snapshots.putIfAbsent(entry.key, () => entry.value);
  }

  // Data from before devices were told apart travels as throws whatever the
  // range asked for, because there is no snapshot it could safely be folded
  // into: not this device's, which would hand it to whoever it came from as
  // ours. The set is finite and does not grow, and one sync per device pair
  // replaces it with data that knows where it is from.
  travelling.addAll(
    (byOrigin[kLegacyOrigin] ?? const <DartThrow>[]).map(
      (t) => (kLegacyOrigin, t),
    ),
  );
  final legacySnapshot = stored[kLegacyOrigin];
  if (legacySnapshot != null && legacySnapshot.isNotEmpty) {
    snapshots[kLegacyOrigin] = legacySnapshot;
  }

  travelling.sort((a, b) => a.$2.thrownAt.compareTo(b.$2.thrownAt));

  final origins = [
    for (final device in {...snapshots.keys, ...travelling.map((t) => t.$1)})
      SyncOrigin(device: device, snapshotJson: snapshots[device] ?? ''),
  ];

  return SyncPacket(
    version: 2,
    senderDevice: senderDevice,
    senderDeviceId: deviceId,
    playerUuid: player.uuid,
    playerName: player.name,
    favoriteDoubles: player.favoriteDoubles,
    origins: origins,
    throwOrigins: [for (final t in travelling) t.$1],
    // Everything added together, for an app version that knows no origins and
    // reads this field alone.
    localStatsJson: DbHelper.mergeSnapshots(origins.map((o) => o.snapshotJson)),
    rangeDays: range.days,
    stats: SyncStats(
      totalDarts: totalDarts,
      totalVisits: totalVisits,
      average: double.parse(avg.toStringAsFixed(2)),
      legsWon: totalLegs,
      highestVisit: highestVisit,
      busts: totalBusts,
      count180: total180,
    ),
    throws: [for (final t in travelling) SyncThrow.fromDartThrow(t.$2)],
  );
}

/// QR/Wi-Fi device-to-device sync screen with Send and Receive tabs for
/// transferring a player's stats between devices.
class SyncScreen extends StatefulWidget {
  final Player? initialPlayer;

  /// A profile the system handed the app, to be imported straight away.
  ///
  /// The same text a QR code carries, so it runs through the same read, the
  /// same name conflict check and the same confirmation as a scanned one.
  final String? incomingPayload;

  /// Whether this sits inside a pane that already has a title bar of its own,
  /// as the player list gives it on a tablet. The tabs then head the body
  /// instead of hanging under an app bar that is not there.
  final bool embedded;

  const SyncScreen({
    super.key,
    this.initialPlayer,
    this.incomingPayload,
    this.embedded = false,
  });

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    // Start on Send (index 1) when a player was passed, otherwise Receive (index 0).
    _tab = TabController(
      length: 2,
      initialIndex: widget.initialPlayer != null ? 1 : 0,
      vsync: this,
    );
    // The send tab has a code on it and, for a large history, a server behind
    // it. Both stop when the tab is left, which the tab itself has to be told.
    _tab.addListener(() {
      if (!_tab.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: TabBar(
          controller: _tab,
          tabs: [
            Tab(
              icon: const Icon(Icons.download_rounded),
              text: context.l10n.syncReceive,
            ),
            Tab(
              icon: const Icon(Icons.upload_rounded),
              text: context.l10n.syncSend,
            ),
          ],
        ),
      ),
    );

    // One column, on every device and in either orientation: the screen is a
    // picker over a code, and a code beside its picker was tried and read
    // worse, not least because the pane it now lives in is already half a
    // screen wide.
    final body = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: TabBarView(
          controller: _tab,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _ReceiverTab(incomingPayload: widget.incomingPayload),
            _SenderTab(
              initialPlayer: widget.initialPlayer,
              visible: _tab.index == 1,
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(context.l10n.syncTitle),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(kTextTabBarHeight),
                child: tabs,
              ),
            ),
      body: widget.embedded
          ? Column(
              children: [
                tabs,
                Expanded(child: body),
              ],
            )
          : body,
    );
  }
}

// ── Sender ────────────────────────────────────────────────────────────────────

/// Send tab: pick a player and a range, then hand their stats over by whichever
/// transport the resulting payload calls for.
class _SenderTab extends StatefulWidget {
  final Player? initialPlayer;

  /// Whether this tab is the one on screen. A code nobody can see is not worth
  /// encoding, and a server nobody can be handed the code to is not worth
  /// keeping open.
  final bool visible;

  const _SenderTab({this.initialPlayer, this.visible = true});

  @override
  State<_SenderTab> createState() => _SenderTabState();
}

class _SenderTabState extends State<_SenderTab>
    with WidgetsBindingObserver, _PacketImport {
  Player? _selectedPlayer;
  SyncRange _range = SyncRange.all;

  // Prepared payload
  SyncPacket? _packet;
  SyncTransmission? _transmission;
  bool _preparing = false;

  // Animated QR
  SyncFountainEncoder? _encoder;
  Timer? _frameTimer;

  /// Whether the animated code is running. It waits for the sender to say so:
  /// a stream of codes nobody is holding a camera to is ten encodes a second
  /// into a picture that is only being looked at.
  bool _streaming = false;

  /// The frame counter is a notifier rather than plain state because it moves
  /// ten times a second. Through `setState` every tick would rebuild the whole
  /// tab, dropdown and range picker included, when the only thing that changed
  /// is the code itself.
  final _frameIndex = ValueNotifier<int>(0);

  // Server transport, only started when the user asks for it
  final _server = SyncServer();
  TransferInvite? _invite;
  bool _serverStarting = false;

  /// Set while the approval dialog for a waiting peer is on screen, so a second
  /// request from the same peer does not open a second one.
  bool _askingApproval = false;

  /// Set once the exchange is over and the server has stopped itself.
  bool _served = false;

  /// Why the server would not start, or null. Shown in place of the hint above
  /// the button.
  String? _startError;

  /// Whether the time range picker is folded open.
  bool _rangeOpen = false;

  /// Anchor for the share sheet, which fails on an iPad without one.
  final _shareKey = GlobalKey();

  /// Set while the share sheet is being put together.
  bool _sharing = false;

  /// Which way the two devices reach each other.
  TransferRoute _route = TransferRoute.sharedWifi;

  /// Whether this device can raise a network of its own. False on iOS and
  /// below Android 13, and then the route is not a choice at all.
  bool _canHostNetwork = false;

  /// The network this device raised, or null when the transfer runs over a
  /// Wi-Fi both devices were already on.
  HotspotCredentials? _hotspot;

  /// Watches for the system taking the raised network down under the transfer.
  StreamSubscription<void>? _hotspotStopped;

  /// What went wrong with the packet the peer sent back, if anything. The
  /// outgoing half already succeeded at that point, so this is reported next to
  /// the confirmation rather than in place of it.
  String? _returnError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalHotspot.isSupported().then((supported) {
      if (mounted) setState(() => _canHostNetwork = supported);
    });
    // Wi-Fi switched off under a running hotspot takes the network with it.
    // Without this the screen keeps showing a code for a network that is gone.
    _hotspotStopped = LocalHotspot.onStopped.listen((_) {
      if (!mounted || _hotspot == null) return;
      _stopServer();
      setState(() => _startError = context.l10n.hotspotStopped);
    });
    if (widget.initialPlayer != null) {
      _selectedPlayer = widget.initialPlayer;
      // A player who has synced before rarely needs their whole history again.
      _range = widget.initialPlayer!.lastSyncedAt == null
          ? SyncRange.all
          : SyncRange.week;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prepare();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _SenderTab old) {
    super.didUpdateWidget(old);
    if (old.visible && !widget.visible) _hide();
  }

  /// Takes the transfer down when the tab is left: the code goes back to
  /// waiting, and the server stops rather than sitting on a payload nobody can
  /// still be given the code to.
  void _hide() {
    _frameTimer?.cancel();
    if (_streaming) setState(() => _streaming = false);
    if (_server.isRunning) _stopServer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _frameIndex.dispose();
    _hotspotStopped?.cancel();
    _server.state.removeListener(_onServerState);
    _server.stop();
    // Nothing about a transfer survives the screen it ran on. A network left
    // up costs battery and sits in everyone's Wi-Fi list.
    if (_hotspot != null) LocalHotspot.stop();
    _server.dispose();
    super.dispose();
  }

  /// Takes the running transfer down when the app goes to the background and
  /// picks the animated code back up on return.
  ///
  /// A sender nobody can see is pure waste: the frame loop would keep encoding
  /// ten codes a second into a surface that is never drawn, and the server
  /// would keep a socket open with the payload behind it. The server does not
  /// come back on its own, because its pairing number and token belong to the
  /// session that just ended, so the user starts a fresh one from the button.
  /// An approval dialog is dismissed along with it, otherwise it would return
  /// asking about a peer that can no longer be let in.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _frameTimer?.cancel();
        if (_askingApproval) {
          Navigator.of(context, rootNavigator: true).pop(false);
        }
        if (_server.isRunning) _stopServer();
      case AppLifecycleState.resumed:
        if (_encoder != null && _streaming) _startFrameLoop();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Follows the transfer: asks the user about a waiting peer, and shuts the
  /// server down again once the payload has gone out.
  void _onServerState() {
    switch (_server.state.value) {
      case SyncServerState.pending:
        _askApproval();
      case SyncServerState.rejected:
        // Turning a device away leaves the server refusing everyone, so it
        // comes down rather than sitting there saying no to the next attempt
        // as well.
        _finishServing();
      case SyncServerState.returned:
        _finishExchange();
      case SyncServerState.waiting:
      case SyncServerState.approved:
      // The payload is out but the session is not over: the other device still
      // owes its own side, which is what makes one pairing reconcile both.
      case SyncServerState.served:
        if (mounted) setState(() {});
    }
  }

  /// Shows the peer's request with the pairing number and acts on the answer.
  Future<void> _askApproval() async {
    if (_askingApproval || !mounted) return;
    _askingApproval = true;

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PairingDialog(pin: _server.pin),
    );

    _askingApproval = false;
    if (approved == true) {
      _server.approve();
    } else {
      _server.reject();
    }
  }

  /// Stops the server once the session is over, one way or the other.
  Future<void> _finishServing() async {
    final sent = _server.state.value == SyncServerState.served;
    await _server.stop();
    await _dropNetwork();
    if (mounted)
      setState(() {
        _invite = null;
        _served = sent;
      });
  }

  /// Closes the session once the peer has answered, and imports what it sent.
  ///
  /// The outgoing half is already done by this point, so a return leg that
  /// brings nothing, or brings something unreadable, is reported beside the
  /// confirmation instead of turning the whole transfer into a failure.
  Future<void> _finishExchange() async {
    final payload = _server.returnedPayload;
    await _server.stop();
    await _dropNetwork();
    if (!mounted) return;
    setState(() {
      _invite = null;
      _served = true;
      _returnError = null;
    });

    if (payload == null) return;

    SyncPacket packet;
    try {
      packet = decodeSyncPayload(payload);
    } catch (e) {
      if (mounted) {
        setState(
          () => _returnError =
              '${context.l10n.syncReadFailed}\n\n'
              '${context.l10n.error}: $e',
        );
      }
      return;
    }

    if (!mounted) return;
    final imported = await importPacket(packet);
    // Back to the player list, where the profile that just changed is waiting.
    if (imported && mounted) Navigator.of(context).pop();
  }

  // ── Preparing the payload ─────────────────────────────────────────────────

  /// Builds and encodes the packet for the current player and range, then picks
  /// the transport from how large it turned out.
  Future<void> _prepare() async {
    final player = _selectedPlayer;
    if (player == null) return;

    _frameTimer?.cancel();
    if (_server.isRunning) await _server.stop();

    setState(() {
      _preparing = true;
      _packet = null;
      _transmission = null;
      _encoder = null;
      _streaming = false;
      _invite = null;
      _served = false;
    });

    final packet = await buildSyncPacket(
      player,
      await DeviceDescription.label,
      _range,
    );
    final transmission = prepareTransmission(packet);

    if (!mounted) return;
    setState(() {
      _packet = packet;
      _transmission = transmission;
      _encoder = transmission.transport == SyncTransport.animatedQr
          ? SyncFountainEncoder(transmission.data)
          : null;
      _streaming = false;
      _preparing = false;
    });
    _frameIndex.value = 0;
  }

  /// Starts the animated code once the receiver is ready for it.
  void _startStreaming() {
    setState(() => _streaming = true);
    _startFrameLoop();
  }

  /// Puts the animated code back behind its glass.
  void _stopStreaming() {
    _frameTimer?.cancel();
    setState(() => _streaming = false);
  }

  /// Drives the endless stream of fountain coded frames.
  ///
  /// There is no loop to come round: every tick is a fresh combination of the
  /// payload's blocks, and the receiver stops as soon as it has caught enough
  /// of them, whichever ones those happen to be.
  void _startFrameLoop() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(kChunkFrameDuration, (_) {
      if (!mounted || _encoder == null) return;
      _frameIndex.value++;
    });
  }

  /// Roughly how long the animated transfer takes, for the info line.
  int get _transferSeconds =>
      (_transmission!.estimatedDuration.inMilliseconds / 1000).ceil();

  // ── Server transport ──────────────────────────────────────────────────────

  /// Starts the local HTTP server serving the prepared packet and shows the
  /// connection QR the receiver scans.
  ///
  /// Every failure lands in the error line and releases the button. Without the
  /// catch a device with Wi-Fi off left the button spinning for the rest of the
  /// session, with nothing on screen to say why.
  Future<void> _startServer() async {
    final transmission = _transmission;
    if (transmission == null) return;
    setState(() {
      _serverStarting = true;
      _served = false;
      _startError = null;
    });

    try {
      if (_server.isRunning) await _server.stop();
      await _dropNetwork();

      // The network first, then the server: the address a peer reaches this
      // device on only exists once the network is up, and the server reads the
      // addresses as it binds.
      final hotspot = _route == TransferRoute.ownNetwork
          ? await LocalHotspot.start()
          : null;
      _hotspot = hotspot;

      _server.state.removeListener(_onServerState);
      final invite = await _server.start(
        utf8.encode(transmission.payload),
        hotspot: hotspot,
      );
      _server.state.addListener(_onServerState);

      if (!mounted) return;
      setState(() {
        _invite = invite;
        _serverStarting = false;
      });
    } catch (e) {
      await _dropNetwork();
      if (!mounted) return;
      setState(() {
        _serverStarting = false;
        _startError = transferStartMessage(context, e);
      });
    }
  }

  /// Stops the transfer server and clears its connection details.
  Future<void> _stopServer() async {
    await _server.stop();
    await _dropNetwork();
    if (mounted) setState(() => _invite = null);
  }

  /// Takes the raised network down, if this transfer raised one.
  ///
  /// Has to run on every way out, the failures included: the screen is the only
  /// thing that knows the network was for this transfer and nothing else.
  Future<void> _dropNetwork() async {
    if (_hotspot == null) return;
    _hotspot = null;
    await LocalHotspot.stop();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Switches to a different player and prepares their payload.
  void _onPlayerChanged(Player? p) {
    if (p == null || p.id == _selectedPlayer?.id) return;
    setState(() => _selectedPlayer = p);
    _prepare();
  }

  /// Switches the range and prepares the payload again.
  void _onRangeChanged(SyncRange range) {
    if (range == _range) return;
    setState(() => _range = range);
    _prepare();
  }

  /// The time range, folded away until somebody wants it.
  ///
  /// Almost nobody narrows it, and open it put two paragraphs about visits,
  /// totals and device attribution in front of the one thing this screen exists
  /// for. What stays out is the line that says how much there is and which way
  /// it will travel, because that is the answer to "is this going to work",
  /// which is the question the screen actually raises.
  List<Widget> _rangeSection(
    AppLocalizations l,
    ThemeData theme,
    ColorScheme cs,
    SyncPacket? packet,
  ) {
    final locked = _preparing || _server.isRunning;
    return [
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: locked ? null : () => setState(() => _rangeOpen = !_rangeOpen),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${l.syncRangeLabel}: ${_rangeLabel(l, _range)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(
                _rangeOpen ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
      if (_rangeOpen) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SyncRange.values
              .map(
                (range) => ChoiceChip(
                  label: Text(_rangeLabel(l, range)),
                  selected: _range == range,
                  onSelected: locked ? null : (_) => _onRangeChanged(range),
                ),
              )
              .toList(),
        ),
        if (packet != null && !_preparing && _range != SyncRange.all) ...[
          const SizedBox(height: 8),
          Text(
            l.syncRangeNote,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          // Only worth saying while a range is picked: that is when the count
          // stops moving and the picker looks broken.
          if (_legacyCount(packet) > 0) ...[
            const SizedBox(height: 6),
            Text(
              l.syncLegacyNote,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ],
      if (packet != null && !_preparing) ...[
        const SizedBox(height: 10),
        Text(
          '${_visitCountLabel(l, packet)} · ${_transportLabel(l)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    ];
  }

  /// The localized label for [range].
  String _rangeLabel(AppLocalizations l, SyncRange range) =>
      _rangeLabelForDays(l, range.days);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;
    final players = context.watch<PlayersProvider>().players;

    // Resolve to provider's object so DropdownButton equality works.
    Player? dropdownValue;
    if (_selectedPlayer != null) {
      try {
        dropdownValue = players.firstWhere((p) => p.id == _selectedPlayer!.id);
      } catch (_) {
        dropdownValue = null;
      }
    }

    final picker = <Widget>[
      // ── Description ───────────────────────────────────────────────────
      Text(
        l.syncSendDesc,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 16),

      // ── Player dropdown ───────────────────────────────────────────────
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Player>(
              value: dropdownValue,
              hint: Text(l.selectPlayer),
              isExpanded: true,
              items: players
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: cs.primaryContainer,
                            child: Text(
                              p.name.isNotEmpty ? p.name[0].toUpperCase() : "?",
                              style: TextStyle(
                                color: cs.onPrimaryContainer,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(p.name),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _server.isRunning ? null : _onPlayerChanged,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),

      // ── Range picker ──────────────────────────────────────────────────
      _buildRangePicker(l, cs, theme),
    ];

    final transport = _buildTransportContent(l, cs, theme);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...picker,
        const SizedBox(height: 12),
        transport,
        if (_transmission != null && !_preparing) ...[
          const SizedBox(height: 20),
          _buildShareFile(l),
          const SizedBox(height: 8),
          Text(
            // Tapping the file is enough on iOS. On Android a file manager
            // that does not know the extension offers no way to open it at
            // all, so the route that works has to be the one named.
            Platform.isIOS ? l.syncShareFileHint : l.syncShareFileHintShare,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// Offers the same profile as a file, for whatever the system can carry one
  /// with.
  ///
  /// The answer for two iPhones and no network between them: Apple lets no app
  /// raise one, so AirDrop through the share sheet is what is left. It works
  /// for mail and a chat just as well, and it is one direction only, like a
  /// code on a screen.
  Widget _buildShareFile(AppLocalizations l) => OutlinedButton.icon(
    key: _shareKey,
    onPressed: _sharing ? null : _shareFile,
    icon: _sharing
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.ios_share),
    label: Text(l.syncShareFile),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
    ),
  );

  /// Writes the payload out and hands it to the share sheet.
  Future<void> _shareFile() async {
    final transmission = _transmission;
    final player = _selectedPlayer;
    if (transmission == null || player == null) return;

    setState(() => _sharing = true);
    try {
      // Anchored on the button, because a popover without an anchor fails
      // instead of opening on an iPad.
      final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box == null || !box.hasSize
          ? null
          : box.localToGlobal(Offset.zero) & box.size;

      await shareSyncFile(
        transmission.payload,
        playerName: player.name,
        origin: origin,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _startError = '${context.l10n.error}: $e');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Builds the range chips plus the line that translates the current choice
  /// into throws and the transport they call for.
  Widget _buildRangePicker(
    AppLocalizations l,
    ColorScheme cs,
    ThemeData theme,
  ) {
    final packet = _packet;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [..._rangeSection(l, theme, cs, packet)],
        ),
      ),
    );
  }

  /// How many of the packet's throws predate devices being told apart.
  ///
  /// They travel whatever the range says, which is what makes the count look
  /// stuck on a device that synced under an older version.
  int _legacyCount(SyncPacket packet) =>
      packet.throwOrigins.where((o) => o == kLegacyOrigin).length;

  /// What the packet carries as throws, and how much of that the range has no
  /// say over.
  String _visitCountLabel(AppLocalizations l, SyncPacket packet) {
    final total = l.syncVisitCount(packet.throws.length);
    final legacy = _legacyCount(packet);
    return legacy == 0 ? total : '$total, ${l.syncLegacyShare(legacy)}';
  }

  /// How the current payload will travel, in words.
  String _transportLabel(AppLocalizations l) =>
      switch (_transmission!.transport) {
        SyncTransport.staticQr => l.syncViaStaticQr,
        SyncTransport.animatedQr => l.syncViaAnimatedQr(_transferSeconds),
        SyncTransport.server => l.syncViaServer,
      };

  /// Builds whichever transport the prepared payload ended up needing.
  Widget _buildTransportContent(
    AppLocalizations l,
    ColorScheme cs,
    ThemeData theme,
  ) {
    if (_selectedPlayer == null) return const SizedBox.shrink();

    if (_preparing || _transmission == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return switch (_transmission!.transport) {
      SyncTransport.staticQr => _buildStaticQr(l, cs, theme),
      SyncTransport.animatedQr => _buildAnimatedQr(l, cs, theme),
      SyncTransport.server => _buildServer(l, cs, theme),
    };
  }

  /// Shows the whole packet as one still QR code.
  Widget _buildStaticQr(AppLocalizations l, ColorScheme cs, ThemeData theme) =>
      Column(
        children: [
          _qrCard(_transmission!.payload),
          const SizedBox(height: 8),
          Text(
            l.profileAndStats,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );

  /// Shows the packet as an endless stream of QR codes.
  ///
  /// The progress bar is deliberately indeterminate. The sender has no idea how
  /// far the receiver has got, and a bar counting frames sent would suggest it
  /// does; what matters is only that the stream is running.
  Widget _buildAnimatedQr(AppLocalizations l, ColorScheme cs, ThemeData theme) {
    if (!_streaming) {
      return Column(
        children: [
          // The first frame, behind glass: enough to see that a code is
          // waiting, not enough to scan half a transfer by accident.
          Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: _qrCard(_encoder!.frameAt(0)),
                ),
              ),
              IconButton.filled(
                onPressed: _startStreaming,
                iconSize: 44,
                padding: const EdgeInsets.all(20),
                icon: const Icon(Icons.play_arrow_rounded),
                tooltip: l.syncStartStream,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l.syncStartStreamHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // The code stops where it was started: on a tap on the code itself.
        GestureDetector(
          onTap: _stopStreaming,
          child: ValueListenableBuilder<int>(
            valueListenable: _frameIndex,
            builder: (_, index, _) => _qrCard(_encoder!.frameAt(index)),
          ),
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 8),
        Text(
          l.syncStopStreamHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Offers the Wi-Fi transfer for payloads no QR code can carry.
  Widget _buildServer(AppLocalizations l, ColorScheme cs, ThemeData theme) {
    if (_invite == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_served) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  l.syncServerSent,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _returnError ?? l.syncServerSentHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _returnError == null ? cs.onSurfaceVariant : cs.error,
              ),
            ),
            const SizedBox(height: 16),
          ],
          TransferRouteSelector(
            value: _route,
            ownNetworkAvailable: _canHostNetwork,
            // An Android too old to raise a network needs no explanation: the
            // answer there is a Wi-Fi, which the hint above already names.
            unavailableHint: Platform.isIOS ? l.syncIosNoOwnNetwork : null,
            enabled: !_serverStarting,
            onChanged: (route) => setState(() {
              _route = route;
              _startError = null;
            }),
          ),
          if (_startError != null) ...[
            const SizedBox(height: 12),
            Text(
              _startError!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _serverStarting ? null : _startServer,
            icon: _serverStarting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(l.startServer),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      );
    }

    final invite = _invite!;
    // The payload is out and the other device is putting its own together. The
    // code is gone from the screen by then: scanning it again would only reach
    // a session that is already spoken for.
    final awaitingReturn = _server.state.value == SyncServerState.served;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _stopServer,
          icon: const Icon(Icons.stop_circle_outlined),
          label: Text(l.stopServer),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 20),
        if (awaitingReturn) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(
            l.syncAwaitingReturn,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ] else ...[
          _qrCard(invite.qrPayload(kSyncWifiPrefix)),
          if (_hotspot != null) ...[
            const SizedBox(height: 16),
            Text(
              '${l.hotspotNetworkName(_hotspot!.ssid)}\n${l.hotspotSendHint}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// Every code on this tab carries the player's name above it, so a sender
  /// with several profiles can see whose history is on screen.
  Widget _qrCard(String data) =>
      PairingQrCard(data: data, title: _selectedPlayer!.name);
}

// ── Receiver ──────────────────────────────────────────────────────────────────

/// Receive tab: scans a QR code (or connects over Wi-Fi) to import a player's
/// synced stats, resolving name conflicts and confirming before importing.
class _ReceiverTab extends StatefulWidget {
  /// A profile handed over by another app, imported as if it had been scanned.
  final String? incomingPayload;

  const _ReceiverTab({this.incomingPayload});

  @override
  State<_ReceiverTab> createState() => _ReceiverTabState();
}

class _ReceiverTabState extends State<_ReceiverTab> with _PacketImport {
  bool _scanning = false;
  bool _fetching = false;
  String? _error;

  /// Rebuilds the payload from the frames of an animated QR code.
  final _decoder = SyncFountainDecoder();

  /// Set once a payload is complete, so the detections that keep arriving while
  /// the confirmation dialog opens are ignored.
  bool _handled = false;

  /// The pairing number a Wi-Fi transfer is waiting on, shown so the user can
  /// compare it against the sending device.
  String? _pairingPin;

  /// The network being joined, while that is happening. Null the rest of the
  /// time.
  String? _joiningNetwork;

  /// Set once this tab joined a network, so it can be left again.
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    // The camera comes up with the tab rather than behind a button. There is
    // nothing else on this tab to do, and the backup screen has always shown
    // its scanner straight away. Leaving the tab takes it away again: a
    // `TabBarView` does not build the child that is not on screen, so the
    // camera goes with it and needs no separate switch.
    _scanning = true;

    final incoming = widget.incomingPayload;
    if (incoming != null) {
      _handled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _finishScan(() async => decodeSyncPayload(incoming));
      });
    }
  }

  @override
  void dispose() {
    // A phone left on a network with no internet on it is the one thing this
    // must never do, so leaving happens whatever the transfer did.
    if (_joined) WifiJoin.leave();
    super.dispose();
  }

  /// Leaves the transfer network, if this tab joined one.
  Future<void> _leaveNetwork() async {
    if (!_joined) return;
    _joined = false;
    await WifiJoin.leave();
  }

  /// Joins the network the invitation names, when it names one.
  ///
  /// Nothing to do for a transfer over a shared Wi-Fi, which is what a null
  /// [TransferInvite.hotspot] means. When the join is not possible from inside
  /// the app the credentials go on screen instead, and the user picks the
  /// network in the system settings themselves.
  Future<void> _joinIfNeeded(TransferInvite invite) async {
    final hotspot = invite.hotspot;
    if (hotspot == null) return;

    if (mounted) setState(() => _joiningNetwork = hotspot.ssid);
    try {
      if (!await WifiJoin.isSupported()) {
        throw const HotspotException(HotspotFailure.unsupported);
      }
      await WifiJoin.join(hotspot);
      _joined = true;
    } finally {
      if (mounted) setState(() => _joiningNetwork = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final l = context.l10n;

    // ── What the tab says about itself ──────────────────────────────────────
    final about = <Widget>[
      Text(
        l.syncReceiveDesc,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _error!,
            style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
          ),
        ),
      ],
    ];

    // ── The camera, or the button that turns it on ──────────────────────────
    final Widget stage;
    if (_fetching) {
      stage = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            // Joining comes before the pairing number and takes long enough on
            // its own that a bare spinner reads as a transfer that died.
            if (_joiningNetwork != null) ...[
              const SizedBox(height: 20),
              Text(
                l.hotspotJoining(_joiningNetwork!),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            if (_pairingPin != null) ...[
              const SizedBox(height: 20),
              Text(
                _pairingPin!,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l.syncPairWaiting,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
    } else if (_scanning) {
      stage = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: QrScanner(onScanned: _onScanned)),
          if (_decoder.sourceBlocks > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _decoder.solved / _decoder.sourceBlocks,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              '${l.syncKeepHolding}\n'
              '${l.syncScanProgress(_decoder.solved, _decoder.sourceBlocks)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    } else {
      stage = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...about,
          const SizedBox(height: 16),
          if (_scanning || _fetching) Expanded(child: stage) else stage,
        ],
      ),
    );
  }

  /// Handles one camera detection.
  ///
  /// The camera keeps firing while an animated code plays, so most detections
  /// only add a frame and update the progress. Anything that is not a frame is
  /// a whole payload or a connection QR, and finishes the scan right away.
  void _onScanned(String raw) async {
    if (_handled) return;

    if (SyncFountainDecoder.isFrame(raw)) {
      if (_decoder.add(raw) && mounted) setState(() {});
      if (!_decoder.isComplete) return;

      _handled = true;
      // Assembling belongs inside the guarded read, not before it: it verifies
      // the checksum and so throws on a transfer that arrived corrupt. Outside,
      // that exception escapes the scanner callback and leaves the screen with
      // _handled already set, deaf to every further code and showing nothing.
      await _finishScan(() async {
        final data = _decoder.assemble();
        _decoder.reset();
        return decodeSyncBytes(data);
      });
      return;
    }

    _handled = true;

    // ── Whole packet in one code ──────────────────────────────────────────
    if (raw.startsWith(kSyncPrefixV2) || raw.startsWith(kSyncPrefixV1)) {
      await _finishScan(() async => decodeSyncPayload(raw));
      return;
    }

    // ── Wi-Fi transfer ────────────────────────────────────────────────────
    final invite = TransferInvite.parse(raw, prefix: kSyncWifiPrefix);
    if (invite == null) {
      // A backup code is the one wrong code worth naming, because it looks
      // right and belongs to a different screen. The backup screen makes the
      // mirror check for a sync code.
      final isBackupCode =
          TransferInvite.parse(raw, prefix: kBackupWifiPrefix) != null;
      if (isBackupCode) {
        if (mounted) {
          setState(() {
            _scanning = false;
            _error = context.l10n.syncNotBackupCode;
          });
        }
        return;
      }
      await _finishScan(
        () async => throw const FormatException('Not a sync code'),
      );
      return;
    }

    // One client for both directions, so the return leg goes back on the
    // address that answered rather than working through the candidates again.
    final client = SyncClient();
    await _finishScan(
      () async {
        await _joinIfNeeded(invite);
        final payload = await client.fetch(
          invite,
          onPin: (pin) {
            if (mounted) setState(() => _pairingPin = pin);
          },
        );
        return decodeSyncPayload(payload);
      },
      invite: invite,
      client: client,
    );
  }

  /// Closes the camera, resolves [read] into a packet and imports it, turning
  /// any failure into the error banner.
  ///
  /// [invite] is set for a Wi-Fi transfer. It picks the failure message,
  /// because a code that would not decode is not a network problem and pointing
  /// at the Wi-Fi would only mislead, and it is where this device's own side of
  /// the exchange goes back to, over [client].
  Future<void> _finishScan(
    Future<SyncPacket> Function() read, {
    TransferInvite? invite,
    SyncClient? client,
  }) async {
    final overWifi = invite != null;
    setState(() {
      _scanning = false;
      _fetching = true;
      _error = null;
      _pairingPin = null;
    });

    try {
      final packet = await read();
      if (!mounted) return;

      // Before the dialogs, not after: the other device is holding its server
      // open until this answers, and a user reading a confirmation is easily
      // slower than any timeout worth having. The two directions do not depend
      // on each other, so there is nothing to wait for.
      if (invite != null) await _returnOwnSide(packet, invite, client!);
      if (!mounted) return;

      final imported = await importPacket(packet);
      if (!mounted) return;
      setState(() => _fetching = false);
      // Back to the player list, where the imported profile is now waiting.
      // Both ways into this screen come from there, so popping lands on it.
      if (imported) Navigator.of(context).pop();
      return;
    } catch (e) {
      // Back onto the ordinary network before anything else. A retry rejoins,
      // and a user who gives up here should not be left without internet.
      await _leaveNetwork();
      if (mounted) {
        final l = context.l10n;
        setState(() {
          _fetching = false;
          // Rescanning is the retry, so the reason stays above a live camera
          // rather than replacing it with a button that would only turn the
          // camera back on. The decoder is reset with it, or a half-read
          // animated code would poison the next one.
          _scanning = true;
          _handled = false;
          _pairingPin = null;
          _decoder.reset();
          _error = switch (e) {
            // Both of these are ordinary outcomes of a pairing, not faults,
            // and pointing at the Wi-Fi would send the user looking in the
            // wrong place.
            SyncRejectedException() => l.syncRejected,
            TimeoutException() => l.syncNotConfirmed,
            SyncPayloadTooLargeException() => l.syncTooLarge,
            // Nothing on the far side ever answered. That is a different fault
            // from a timeout, and the network is the place to look.
            TransferUnreachableException() =>
              invite?.hotspot != null
                  ? l.syncUnreachableOnHotspot
                  : l.syncUnreachable,
            TransferInviteExpiredException() => l.syncCodeExpired,
            // The network was never joined, so the credentials go on screen and
            // the user does it the long way round rather than being stuck.
            HotspotException() when invite?.hotspot != null =>
              '${l.hotspotJoinFailed}\n\n'
                  '${l.hotspotJoinManually(invite!.hotspot!.ssid, invite.hotspot!.passphrase)}',
            _ =>
              '${overWifi ? l.connectionFailed : l.syncReadFailed}'
                  '\n\n${l.error}: $e',
          };
        });
      }
    }
  }

  /// Sends this device's own history for the same player back over the
  /// connection, so one pairing settles both directions.
  ///
  /// Built before the import rather than after, so what goes back is this
  /// device's own history and not the sender's own data handed straight back to
  /// it. Nothing here is allowed to fail loudly: what was received is already
  /// safe, and the only thing a failure costs is the other direction, which the
  /// user can simply run again. The peer is always answered, with an empty body
  /// when this device does not know the player at all, because it is holding
  /// its server open until it hears something.
  Future<void> _returnOwnSide(
    SyncPacket packet,
    TransferInvite invite,
    SyncClient client,
  ) async {
    var payload = '';
    try {
      final player = await DbHelper.instance.getPlayerByUuid(packet.playerUuid);
      if (player != null) {
        // Encoded straight, with no transport decision to make: this always
        // goes back over the connection it came in on, whatever its size.
        final own = await buildSyncPacket(
          player,
          await DeviceDescription.label,
          SyncRange.all,
        );
        payload = encodeSyncPayload(own);
      }
    } catch (_) {
      payload = '';
    }

    try {
      await client.post(invite, payload);
    } catch (_) {
      // The sender falls back on its own timeout.
    }
  }
}

/// The receiving half of a sync, shared by both tabs.
///
/// A Wi-Fi transfer goes both ways in one pairing, so the sending device
/// imports as well: whatever comes back over the return leg runs through the
/// same questions, the same confirmation and the same writes as a packet that
/// was scanned. One copy of that flow is the point of this mixin. Two would be
/// how the directions start disagreeing about what a name conflict means.
mixin _PacketImport<T extends StatefulWidget> on State<T> {
  /// Common flow: name conflict check → confirm dialog → import. Returns
  /// whether anything was written, so the caller can decide what to do with a
  /// screen that is now showing stale data.
  Future<bool> importPacket(SyncPacket packet) async {
    Player? existing = await DbHelper.instance.getPlayerByUuid(
      packet.playerUuid,
    );
    if (!mounted) return false;

    if (existing == null) {
      final provider = context.read<PlayersProvider>();
      final sameNamePlayer = provider.players
          .where((p) => p.name.toLowerCase() == packet.playerName.toLowerCase())
          .firstOrNull;
      if (sameNamePlayer != null) {
        final resolution = await _showNameConflictDialog(
          packet,
          sameNamePlayer,
        );
        if (!mounted) return false;
        if (resolution == null) {
          return false;
        } else if (resolution == _NameResolution.useExisting) {
          existing = sameNamePlayer;
        } else if (resolution is String) {
          return _doImport(packet.withName(resolution), null);
        }
      }
    }

    final confirmed = await _showConfirmDialog(packet, existing);
    if (!mounted || !confirmed) return false;
    return _doImport(packet, existing);
  }

  /// Prompts the user to resolve a same-name conflict (merge into the existing
  /// player or import under a different name), returning their choice.
  Future<Object?> _showNameConflictDialog(
    SyncPacket packet,
    Player sameNamePlayer,
  ) async {
    final nameCtrl = TextEditingController(
      text: '${packet.playerName} (${context.l10n.guest})',
    );
    return showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) {
          final l = ctx.l10n;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth(ctx)),
              child: AlertDialog(
                title: Text(l.nameConflictTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.nameConflictBody(packet.playerName),
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: l.alternativeName,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: Text(l.cancel),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(ctx, _NameResolution.useExisting),
                    child: Text(l.importAs(sameNamePlayer.name)),
                  ),
                  FilledButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      if (name.isNotEmpty) Navigator.pop(ctx, name);
                    },
                    child: Text(l.renameAndImport),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Shows a confirmation dialog summarizing the incoming stats; returns whether
  /// the user approved the import.
  Future<bool> _showConfirmDialog(SyncPacket packet, Player? existing) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(packet: packet, existing: existing),
    );
    return result == true;
  }

  /// Runs the import behind a modal that shows how far it has got and then
  /// reports the outcome. Returns whether it went through.
  ///
  /// A sync can carry tens of thousands of visits, and writing them takes long
  /// enough that a bare spinner leaves the user guessing whether anything is
  /// happening at all.
  Future<bool> _doImport(SyncPacket packet, Player? existing) async {
    final imported = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportProgressDialog(
        run: (report) => _writeImport(packet, existing, report),
      ),
    );
    return imported == true;
  }

  /// Persists the incoming packet: updates the existing player or creates a new
  /// one, stores the received stats snapshot and writes the throws, reporting
  /// progress through [report]. Returns the message to show when it is done.
  Future<String> _writeImport(
    SyncPacket packet,
    Player? existing,
    void Function(int done, int total) report,
  ) async {
    final provider = context.read<PlayersProvider>();
    final l = context.l10n;
    final db = DbHelper.instance;
    final statsJson = jsonEncode(packet.stats.toJson());
    final now = DateTime.now().millisecondsSinceEpoch;
    final localId = await DeviceIdentity.id;

    int playerId;

    // The player's own snapshot is deliberately left alone. It holds the games
    // this device cleared away itself, which no packet knows about and which
    // overwriting it used to lose without a trace.
    if (existing != null) {
      await provider.updatePlayer(
        existing.copyWith(
          name: packet.playerName,
          favoriteDoubles: packet.favoriteDoubles,
          syncedStats: statsJson,
        ),
      );
      await db.updatePlayerSyncTime(
        existing.id!,
        now,
        syncedStatsJson: statsJson,
      );
      playerId = existing.id!;
    } else {
      final newPlayer = await provider.addPlayer(packet.playerName);
      final updated = Player(
        id: newPlayer.id,
        name: packet.playerName,
        favoriteDoubles: packet.favoriteDoubles,
        uuid: packet.playerUuid,
        lastSyncedAt: now,
        syncedStats: statsJson,
      );
      await db.updatePlayer(updated);
      await provider.load();
      playerId = newPlayer.id!;
    }

    final written = await applySyncedData(
      packet,
      playerId,
      localDevice: localId,
      report: report,
    );

    if (packet.throws.isEmpty) {
      return existing != null
          ? l.updatedMsg(packet.playerName)
          : l.importedMsg(packet.playerName);
    }

    // For display: a new player shows total visits (live plus the historical
    // snapshot), an update shows only the newly added live visits.
    final displayCount = existing != null ? written : packet.stats.totalVisits;

    return existing != null
        ? l.importedWithThrows(packet.playerName, displayCount)
        : l.importedWithCount(packet.playerName, displayCount);
  }
}

/// Writes everything an incoming packet holds for [playerId] apart from the
/// player row itself: one stats snapshot per device the packet knows about, and
/// the throws, each under the device it was played on. Returns how many throws
/// were new to this device.
///
/// The packet is authoritative for what the sending device holds, so its throws
/// and its snapshot replace what an earlier sync from there left behind rather
/// than adding to it: the snapshot may already account for throws that arrived
/// one by one last time, and keeping both would count the same legs twice.
/// What a different device sent stays where it is, and games played on this
/// device are never touched.
///
/// [localDevice] is this device's own id. Anything the packet attributes to it
/// is dropped on the floor: those throws and those numbers were produced here,
/// they are still here, and taking them back in is exactly how a sync that goes
/// both ways starts counting a leg twice.
@visibleForTesting
Future<int> applySyncedData(
  SyncPacket packet,
  int playerId, {
  required String localDevice,
  void Function(int done, int total)? report,
}) async {
  final db = DbHelper.instance;
  final sender = packet.senderDeviceId;

  // The legacy bucket goes with the sender: what is in it cannot be told from
  // what the packet carries, and two copies of one history is the error that
  // cannot be seen afterwards.
  await db.deleteSyncedThrowsForPlayer(
    playerId,
    origins: {sender, kLegacyOrigin},
  );
  await db.deleteOriginSnapshots(playerId, {sender, kLegacyOrigin});

  final origins = packet.origins.isNotEmpty
      ? packet.origins
      : [
          // A packet from before origins existed says nothing about where its
          // numbers were produced, only that they were not produced here.
          if (packet.localStatsJson != null)
            SyncOrigin(device: sender, snapshotJson: packet.localStatsJson!),
        ];
  await db.replaceOriginSnapshots(playerId, origins, localDevice: localDevice);

  if (packet.throws.isEmpty) return 0;

  final known = await db.getThrowTimestampsForPlayer(playerId);

  // Grouped by the device each throw was played on, so a device passing on
  // what it received does not make it its own.
  final byOrigin = <String, List<SyncThrow>>{};
  for (var i = 0; i < packet.throws.length; i++) {
    final t = packet.throws[i];
    if (known.contains(t.thrownAt)) continue;

    final origin = packet.originOfThrow(i);
    if (origin == localDevice) continue;

    byOrigin.putIfAbsent(origin, () => []).add(t);
  }

  final total = byOrigin.values.fold(0, (sum, list) => sum + list.length);
  var done = 0;

  for (final entry in byOrigin.entries) {
    final throws = entry.value;
    final gameId = await db.createSyncGame(
      throws.first.remainingBefore + throws.first.score,
      originDevice: entry.key,
    );

    // Written in slices so the modal can move between them. One batch for
    // everything would be marginally quicker and show nothing until the end.
    const sliceSize = 500;
    for (var start = 0; start < throws.length; start += sliceSize) {
      final end = min(start + sliceSize, throws.length);
      await db.insertSyncedThrows(
        playerId,
        gameId,
        throws
            .sublist(start, end)
            .map((t) => t.toDartThrow(gameId: gameId, playerId: playerId))
            .toList(),
      );
      done += end - start;
      report?.call(done, total);
    }
  }

  return total;
}

// ── Import progress ───────────────────────────────────────────────────────────

/// Runs an import, showing its progress, and stays open on the result.
///
/// The user cannot dismiss it while the writing is going on, because a half
/// written import is exactly the state the rest of the sync works hard to
/// avoid.
class _ImportProgressDialog extends StatefulWidget {
  /// The work to run. It reports how many visits of how many are written and
  /// returns the message to show when it finishes.
  final Future<String> Function(void Function(int done, int total)) run;

  const _ImportProgressDialog({required this.run});

  @override
  State<_ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<_ImportProgressDialog> {
  int _done = 0;
  int _total = 0;
  String? _message;
  String? _error;

  bool get _running => _message == null && _error == null;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Runs the import and holds on to whatever it produced.
  Future<void> _start() async {
    try {
      final message = await widget.run((done, total) {
        if (mounted)
          setState(() {
            _done = done;
            _total = total;
          });
      });
      if (mounted) setState(() => _message = message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    return PopScope(
      canPop: !_running,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
          child: AlertDialog(
            title: Text(
              _running
                  ? l.syncImporting
                  : _error != null
                  ? l.syncImportFailed
                  : l.syncImportDone,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _running
                  ? [
                      LinearProgressIndicator(
                        value: _total == 0 ? null : _done / _total,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      if (_total > 0) ...[
                        const SizedBox(height: 10),
                        Text(
                          l.syncImportProgress(_done, _total),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ]
                  : [
                      Icon(
                        _error != null
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        size: 44,
                        color: _error != null ? cs.error : Colors.green,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error ?? _message!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
            ),
            actions: _running
                ? null
                : [
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _error == null),
                      child: Text(l.ok),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

// ── Confirmation dialog ───────────────────────────────────────────────────────

/// Dialog summarizing an incoming sync packet's stats and asking to confirm import.
class _ConfirmDialog extends StatelessWidget {
  final SyncPacket packet;
  final Player? existing;

  const _ConfirmDialog({required this.packet, this.existing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isNew = existing == null;
    final s = packet.stats;
    final l = context.l10n;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: AlertDialog(
          title: Text(isNew ? l.importNewPlayer : l.updatePlayer),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isNew ? cs.secondaryContainer : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: isNew ? cs.secondary : cs.primary,
                      child: Text(
                        packet.playerName.isNotEmpty
                            ? packet.playerName[0].toUpperCase()
                            : "?",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            packet.playerName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (packet.favoriteDoubles.isNotEmpty)
                            Text(
                              '${l.doublesLabel}: ${packet.favoriteDoubles}',
                              style: theme.textTheme.bodySmall,
                            ),
                          Text(
                            '${l.fromDevice(packet.senderDevice)}  ·  ${packet.stats.totalVisits} ${l.visits}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            l.syncRangeInPacket(
                              _rangeLabelForDays(l, packet.rangeDays),
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l.statistics,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              _StatLine(l.threeDartAvg, s.average.toStringAsFixed(2)),
              _StatLine(l.legsWon, '${s.legsWon}'),
              _StatLine(l.totalDarts, '${s.totalDarts}'),
              _StatLine(l.highestVisit, '${s.highestVisit}'),
              _StatLine(l.count180, '${s.count180}'),
              if (!isNew) ...[
                const SizedBox(height: 8),
                Text(
                  l.overwriteProfile(existing!.name),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(isNew ? l.import_ : l.update),
            ),
          ],
        ),
      ),
    );
  }
}

/// A label/value line in the import confirmation dialog.
class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  const _StatLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
