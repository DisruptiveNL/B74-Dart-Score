import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/players_provider.dart';
import '../database/db_helper.dart' show BackupInfo;
import '../services/backup_service.dart';
import '../services/local_hotspot.dart';
import '../services/sync_service.dart';
import '../utils/layout.dart';
import '../widgets/wifi_pairing.dart';

/// Which half of the screen the user is in.
/// Where a backup is being sent.
enum _Destination { file, deviceOverWifi, deviceWithoutWifi }

enum _Mode {
  /// The two entries, waiting to be picked.
  idle,

  /// What restoring will do, and the offer to save the current data first.
  restoreWarning,

  /// Where the backup should come from, and the last word before anything is
  /// replaced.
  restoreSource,

  /// Serving this device's database to a peer over the local network.
  sending,

  /// Camera up, waiting for the other device's code.
  receiving,
}

/// Writes the whole local database out, and reads one back in.
///
/// Both halves offer the same two routes, a file or the other device directly.
/// Past that they are deliberately unequal, because they are not equally
/// dangerous. Creating a backup is two taps. Taking one in walks through what a
/// restore costs, the offer to save the current data first, where the file
/// comes from, and finally what was actually found in it, and only then does
/// anything get replaced.
///
/// Whatever is being handed over or taken in is described in the same terms on
/// both sides: when it was made, which device made it, and what is in it.
class BackupScreen extends StatefulWidget {
  /// A backup the system handed the app, to be offered for restoring straight
  /// away.
  ///
  /// It lands on the confirmation, not on the restore: what it holds goes on
  /// screen with the warning beside it, and nothing is replaced until that is
  /// answered. The steps in front of it, the warning page and the offer to save
  /// the current data first, are for somebody hunting for a file. Whoever just
  /// opened one has already decided which file they mean.
  final String? incomingPath;

  const BackupScreen({super.key, this.incomingPath});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  /// Anchor the share sheet on an iPad, where a popover without an anchor
  /// fails instead of opening. One per entry that can start a share, because
  /// only the one on screen has anything to measure.
  final _exportKey = GlobalKey();
  final _saveFirstKey = GlobalKey();

  final SyncServer _server = SyncServer();

  _Mode _mode = _Mode.idle;
  bool _busy = false;
  TransferInvite? _invite;
  bool _sent = false;
  String? _error;

  /// The pairing number this device is waiting on while receiving, shown so the
  /// user can compare it against the sending device.
  String? _pairingPin;

  /// How much of the database has arrived, and how much is coming. Null until
  /// the transfer is actually running.
  (int, int)? _received;

  /// What this device is offering the peer, shown beside the code so the user
  /// can see what is about to leave.
  BackupInfo? _outgoing;

  /// Set while the approval dialog is up, so a peer asking again does not open
  /// a second one.
  bool _askingApproval = false;

  /// Which way the two devices reach each other.
  TransferRoute _route = TransferRoute.sharedWifi;

  /// Whether this device can raise a network of its own. False on iOS and
  /// below Android 13.
  bool _canHostNetwork = false;

  /// The network this device raised, or null when the transfer runs over a
  /// Wi-Fi both devices were already on.
  HotspotCredentials? _hotspot;

  /// Set between the start button and the code appearing.
  bool _starting = false;

  /// The network being joined while receiving, or null.
  String? _joiningNetwork;

  /// Set once this screen joined a network, so it can be left again.
  bool _joined = false;

  /// Watches for the system taking the raised network down under the transfer.
  StreamSubscription<void>? _hotspotStopped;

  @override
  void initState() {
    super.initState();
    _server.state.addListener(_onServerState);
    LocalHotspot.isSupported().then((supported) {
      if (mounted) setState(() => _canHostNetwork = supported);
    });
    final incoming = widget.incomingPath;
    if (incoming != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openIncoming(incoming),
      );
    }
    // Wi-Fi switched off under a running hotspot takes the network with it.
    _hotspotStopped = LocalHotspot.onStopped.listen((_) {
      if (!mounted || _hotspot == null) return;
      unawaited(_dropNetwork());
      setState(() {
        _invite = null;
        _error = context.l10n.hotspotStopped;
      });
    });
  }

  @override
  void dispose() {
    _server.state.removeListener(_onServerState);
    _hotspotStopped?.cancel();
    unawaited(_server.stop());
    // Nothing about a transfer survives the screen it ran on: a network left
    // up costs battery, and a phone left on one with no internet has no route.
    if (_hotspot != null) unawaited(LocalHotspot.stop());
    if (_joined) unawaited(WifiJoin.leave());
    _server.dispose();
    super.dispose();
  }

  /// Reads a backup another app handed over and asks whether to restore it.
  Future<void> _openIncoming(String path) async {
    setState(() => _busy = true);
    try {
      await _confirmAndRestore(await BackupService.open(path));
    } on BackupRejectedException catch (e) {
      if (mounted) _toast(_rejectionMessage(e));
    } catch (e) {
      if (mounted) _toast('${context.l10n.error}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Takes the raised network down, if this transfer raised one.
  Future<void> _dropNetwork() async {
    if (_hotspot == null) return;
    _hotspot = null;
    await LocalHotspot.stop();
  }

  /// Leaves the transfer network, if this screen joined one.
  Future<void> _leaveNetwork() async {
    if (!_joined) return;
    _joined = false;
    await WifiJoin.leave();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.backupTitle),
        leading: _mode == _Mode.idle
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _leaveMode,
              ),
      ),
      body: ListView(
        padding: contentPadding(context, top: 12, bottom: 28, innerH: 14),
        children: switch (_mode) {
          _Mode.idle => _idleBody(l),
          _Mode.restoreWarning => _restoreWarningBody(l),
          _Mode.restoreSource => _restoreSourceBody(l),
          _Mode.sending => _sendingBody(l),
          _Mode.receiving => _receivingBody(l),
        },
      ),
    );
  }

  // ── The two entries ───────────────────────────────────────────────────────

  List<Widget> _idleBody(AppLocalizations l) {
    final cs = Theme.of(context).colorScheme;
    return [
      _note(l.backupWhereHint),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            ListTile(
              key: _exportKey,
              leading: Icon(Icons.save_alt_rounded, color: cs.primary),
              title: Text(l.backupCreate),
              subtitle: Text(l.backupCreateDesc),
              enabled: !_busy,
              onTap: _chooseCreate,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.restore_rounded, color: cs.error),
              title: Text(l.backupRestore),
              subtitle: Text(l.backupRestoreDesc),
              enabled: !_busy,
              onTap: () => setState(() => _mode = _Mode.restoreWarning),
            ),
          ],
        ),
      ),
      if (_busy) ...[
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
      ],
    ];
  }

  /// Asks where the backup should go, connection and all.
  ///
  /// One list rather than a route dialog followed by a connection choice on the
  /// next screen. Nobody thinks of those as two questions; they think about how
  /// it gets across, and seeing every way at once beats guessing that a second
  /// one exists behind the first.
  Future<void> _chooseCreate() async {
    final l = context.l10n;
    final choice = await _askDestination(l);
    if (choice == null || !mounted) return;

    if (choice == _Destination.file) {
      await _export(_exportKey);
      return;
    }

    // The connection is settled before anything is prepared, so the network is
    // up before the server looks for the address to put in the code.
    setState(() {
      _route = choice == _Destination.deviceWithoutWifi
          ? TransferRoute.ownNetwork
          : TransferRoute.sharedWifi;
      _mode = _Mode.sending;
      _sent = false;
      _error = null;
      _invite = null;
      _outgoing = null;
    });
  }

  /// The list of ways a backup can leave this device.
  Future<_Destination?> _askDestination(AppLocalizations l) {
    return showDialog<_Destination>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        Widget option(
          IconData icon,
          String title,
          String hint,
          _Destination value,
        ) => ListTile(
          leading: Icon(icon, color: cs.primary),
          title: Text(title),
          subtitle: Text(hint),
          onTap: () => Navigator.pop(ctx, value),
        );

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
            child: AlertDialog(
              title: Text(l.backupCreate),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  option(
                    Icons.folder_outlined,
                    l.backupToFile,
                    l.backupToFileDesc,
                    _Destination.file,
                  ),
                  option(
                    Icons.wifi_rounded,
                    l.backupToDevice,
                    l.backupToDeviceDesc,
                    _Destination.deviceOverWifi,
                  ),
                  // Only where this device can raise a network. An option that
                  // can never be picked here is not a choice.
                  if (_canHostNetwork)
                    option(
                      Icons.wifi_tethering,
                      l.backupToDeviceDirect,
                      l.backupToDeviceDirectDesc,
                      _Destination.deviceWithoutWifi,
                    ),
                  // An iPhone has no third row, because no app may raise a
                  // hotspot there, so it gets told which routes are left.
                  if (!_canHostNetwork && Platform.isIOS)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        l.backupIosNoOwnNetwork,
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(ctx.l10n.cancel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Restoring, step one: what it costs ────────────────────────────────────

  /// Says what a restore does before anything is picked, and offers to put the
  /// current data somewhere safe first.
  ///
  /// The way out of a restore that turns out to be the wrong one is a copy of
  /// what was there before, and the only moment the user can still make one is
  /// now.
  List<Widget> _restoreWarningBody(AppLocalizations l) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return [
      Card(
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.backupRestoreQ,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l.backupRestoreWarn,
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        l.backupSaveFirstQ,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          key: _saveFirstKey,
          leading: Icon(Icons.save_alt_rounded, color: cs.primary),
          title: Text(l.backupSaveFirst),
          subtitle: Text(l.backupSaveFirstDesc),
          enabled: !_busy,
          onTap: () => _export(_saveFirstKey),
        ),
      ),
      const SizedBox(height: 24),
      if (_busy)
        const Center(child: CircularProgressIndicator())
      else
        FilledButton(
          onPressed: () => setState(() => _mode = _Mode.restoreSource),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text(l.backupContinueAnyway),
        ),
    ];
  }

  // ── Restoring, step two: from where, and the last word ────────────────────

  /// Where the backup comes from. Picking one is the last thing that happens
  /// before the file is read, and the dialog after it names what was found.
  List<Widget> _restoreSourceBody(AppLocalizations l) {
    final cs = Theme.of(context).colorScheme;

    if (_busy) {
      return [const Center(child: CircularProgressIndicator())];
    }

    return [
      _note(l.backupSourceHint),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.folder_outlined, color: cs.primary),
              title: Text(l.backupFromFile),
              subtitle: Text(l.backupFromFileDesc),
              onTap: _restoreFromFile,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.qr_code_scanner_rounded, color: cs.primary),
              title: Text(l.backupFromDevice),
              subtitle: Text(l.backupFromDeviceDesc),
              onTap: () => setState(() {
                _mode = _Mode.receiving;
                _error = null;
              }),
            ),
          ],
        ),
      ),
    ];
  }

  // ── Sending over the network ──────────────────────────────────────────────

  List<Widget> _sendingBody(AppLocalizations l) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_sent) {
      return [
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
              l.backupSent,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _finishToHome,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text(l.done),
        ),
      ];
    }

    final invite = _invite;
    if (invite == null && _starting) {
      return [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Text(
          l.backupSendPrep,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ];
    }

    if (invite == null) {
      // The way across was settled in the dialog that got us here, so all that
      // is left is the go-ahead: this is the moment the database is read out
      // and, on the direct route, a network goes up.
      return [
        _note(
          _route == TransferRoute.ownNetwork
              ? l.routeOwnNetworkHint
              : l.routeSharedWifiHint,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _startSending,
          icon: Icon(
            _route == TransferRoute.ownNetwork
                ? Icons.wifi_tethering
                : Icons.wifi_rounded,
          ),
          label: Text(l.startServer),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ];
    }

    return [
      _note(l.backupSendHint),
      if (_outgoing != null) ...[
        const SizedBox(height: 12),
        _summaryCard(l, _outgoing!, title: l.backupOutgoingTitle),
      ],
      const SizedBox(height: 20),
      ValueListenableBuilder<double>(
        valueListenable: _server.progress,
        builder: (context, progress, child) => progress == 0
            ? child!
            : Column(
                children: [
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l.backupSending(_percent(progress)),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
        child: PairingQrCard(data: invite.qrPayload(kBackupWifiPrefix)),
      ),
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
    ];
  }

  /// A fraction as whole percent, for the transfer labels.
  int _percent(double fraction) => (fraction * 100).round();

  /// Prepares the database and puts it on the network for one peer.
  Future<void> _startSending() async {
    setState(() {
      _starting = true;
      _sent = false;
      _error = null;
      _invite = null;
      _outgoing = null;
    });

    try {
      final (bytes, info) = await BackupService.exportBytes();
      if (!mounted) return;
      setState(() => _outgoing = info);

      if (_server.isRunning) await _server.stop();
      await _dropNetwork();

      // The network first, then the server: the address a peer reaches this
      // device on only exists once the network is up.
      final hotspot = _route == TransferRoute.ownNetwork
          ? await LocalHotspot.start()
          : null;
      _hotspot = hotspot;

      // One way on purpose. A database replaces the device that takes it, so
      // there is nothing it could hand back.
      final invite = await _server.start(
        bytes,
        twoWay: false,
        contentType: ContentType.binary,
        hotspot: hotspot,
      );
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _starting = false;
      });
    } catch (e) {
      await _dropNetwork();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = transferStartMessage(context, e);
      });
    }
  }

  /// Follows the transfer: asks about a waiting peer, and closes the session
  /// once the database is out.
  void _onServerState() {
    switch (_server.state.value) {
      case SyncServerState.pending:
        _askApproval();
      case SyncServerState.served:
      case SyncServerState.rejected:
        _finishSending();
      case SyncServerState.waiting:
      case SyncServerState.approved:
      case SyncServerState.returned:
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

  /// Takes the server down once the session is over, either way.
  Future<void> _finishSending() async {
    final sent = _server.state.value == SyncServerState.served;
    await _server.stop();
    await _dropNetwork();
    if (mounted)
      setState(() {
        _invite = null;
        _sent = sent;
      });
  }

  /// Joins the network the invitation names, when it names one.
  ///
  /// Nothing to do for a transfer over a shared Wi-Fi. When the join cannot be
  /// made from inside the app the credentials go on screen instead, and the
  /// user picks the network in the system settings themselves.
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

  // ── Receiving over the network ────────────────────────────────────────────

  List<Widget> _receivingBody(AppLocalizations l) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_busy) {
      final received = _received;
      return [
        const Center(child: CircularProgressIndicator()),
        // Joining comes before the pairing number and takes long enough on its
        // own that a bare spinner reads as a transfer that died.
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
        // The number both devices show, so the user can tell that the device
        // asking is the one in front of them.
        if (_pairingPin != null) ...[
          const SizedBox(height: 20),
          Text(
            _pairingPin!,
            textAlign: TextAlign.center,
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
        if (received != null && received.$2 > 0) ...[
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: received.$1 / received.$2,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 10),
          Text(
            l.backupReceivingAt(_percent(received.$1 / received.$2)),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text(
            l.backupReceiving,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ];
    }

    return [
      _note(_error ?? l.backupReceiveHint, isError: _error != null),
      const SizedBox(height: 16),
      SizedBox(height: 320, child: QrScanner(onScanned: _onScanned)),
    ];
  }

  /// Reads a scanned code and, if it opens a database transfer, takes it.
  Future<void> _onScanned(String raw) async {
    if (_busy) return;

    final invite = TransferInvite.parse(raw, prefix: kBackupWifiPrefix);
    if (invite == null) {
      // A profile sync code is the one wrong code worth naming, because it
      // looks right and belongs to a different screen.
      final isSyncCode =
          TransferInvite.parse(raw, prefix: kSyncWifiPrefix) != null;
      if (mounted) {
        setState(
          () => _error = isSyncCode
              ? context.l10n.backupNotSyncCode
              : context.l10n.backupNotABackup,
        );
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _pairingPin = null;
      _received = null;
    });
    try {
      await _joinIfNeeded(invite);
      final bytes = await SyncClient().fetchBytes(
        invite,
        onPin: (pin) {
          if (mounted) setState(() => _pairingPin = pin);
        },
        onProgress: (received, total) {
          if (mounted) setState(() => _received = (received, total));
        },
      );
      if (!mounted) return;
      await _confirmAndRestore(await BackupService.acceptTransfer(bytes));
    } on BackupRejectedException catch (e) {
      await _leaveNetwork();
      if (mounted) setState(() => _error = _rejectionMessage(e));
    } catch (e) {
      // Back onto the ordinary network before anything else. A retry rejoins,
      // and a user who gives up here should not be left without internet.
      await _leaveNetwork();
      if (mounted) {
        final l = context.l10n;
        setState(
          () => _error = switch (e) {
            SyncRejectedException() => l.syncRejected,
            TimeoutException() => l.syncNotConfirmed,
            SyncPayloadTooLargeException() => l.syncTooLarge,
            TransferUnreachableException() =>
              invite.hotspot != null
                  ? l.syncUnreachableOnHotspot
                  : l.syncUnreachable,
            TransferInviteExpiredException() => l.syncCodeExpired,
            // The network was never joined, so the credentials go on screen
            // and the user does it the long way round rather than be stuck.
            HotspotException() when invite.hotspot != null =>
              '${l.hotspotJoinFailed}\n\n'
                  '${l.hotspotJoinManually(invite.hotspot!.ssid, invite.hotspot!.passphrase)}',
            _ => '${l.connectionFailed}\n\n${l.error}: $e',
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pairingPin = null;
          _received = null;
          _joiningNetwork = null;
        });
      }
    }
  }

  // ── Shared ────────────────────────────────────────────────────────────────

  /// Copies the database out and hands it to the share sheet, anchored on the
  /// entry the user tapped.
  Future<void> _export(GlobalKey anchor) async {
    final box = anchor.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    setState(() => _busy = true);
    try {
      final shared = await BackupService.exportAndShare(
        sharePositionOrigin: origin,
      );
      if (shared && mounted) _toast(context.l10n.backupCreated);
    } catch (e) {
      if (mounted) _toast('${context.l10n.error}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Picks a backup file and replaces the local data once that is confirmed.
  Future<void> _restoreFromFile() async {
    setState(() => _busy = true);
    try {
      final picked = await BackupService.pick();
      if (picked == null) return;
      if (!mounted) return await picked.discard();
      await _confirmAndRestore(picked);
    } on BackupRejectedException catch (e) {
      if (mounted) _toast(_rejectionMessage(e));
    } catch (e) {
      if (mounted) _toast('${context.l10n.error}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The last step of both routes in: show what is about to replace everything,
  /// and carry it out if the user says so.
  Future<void> _confirmAndRestore(PickedBackup picked) async {
    if (!await _confirm(picked)) return await picked.discard();
    if (!mounted) return await picked.discard();

    await BackupService.restore(picked);
    if (!mounted) return;
    await context.read<PlayersProvider>().load();
    if (!mounted) return;

    _toast(context.l10n.backupRestored);
    // The screens underneath were built from data that no longer exists.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Asks whether [picked] should really replace everything on this device,
  /// showing when it was made and what it contains so two backups can be told
  /// apart.
  Future<bool> _confirm(PickedBackup picked) async {
    final l = context.l10n;
    final info = picked.info;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        // Bounded like every dialog in the sync screen: an AlertDialog left to
        // itself takes the width it is offered, which on a tablet is most of
        // the screen for a few lines of text.
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
            child: AlertDialog(
              title: Text(l.backupRestoreQ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _summaryCard(l, info, title: l.backupIncomingTitle),
                    const SizedBox(height: 14),
                    Text(l.backupRestoreWarn),
                    const SizedBox(height: 10),
                    Text(
                      l.backupDeviceNote,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l.cancel),
                ),
                FilledButton(
                  // Both halves of the pair, not just the background. A
                  // FilledButton left to itself writes in onPrimary, which is
                  // white in both themes, and the dark theme's error is a
                  // light red that white barely shows up on.
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(l.backupRestore),
                ),
              ],
            ),
          ),
        );
      },
    );
    return ok ?? false;
  }

  /// Leaves the backup screen altogether, back to where the user started.
  ///
  /// The transfer is over and there is nothing left to do here, so the way out
  /// is one tap rather than a walk back up through the settings. The server is
  /// shut down by [dispose] on the way.
  void _finishToHome() =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  /// Back to the two entries, shutting down whatever the mode was running.
  ///
  /// A transfer in flight is dropped rather than asked about. The network and
  /// the binding have to be given back on every way out, and a dialog is no
  /// help on the way most transfers are abandoned, which is the app going to
  /// the background.
  Future<void> _leaveMode() async {
    await _server.stop();
    await _dropNetwork();
    await _leaveNetwork();
    if (!mounted) return;
    setState(() {
      _mode = _Mode.idle;
      _invite = null;
      _sent = false;
      _error = null;
    });
  }

  String _rejectionMessage(BackupRejectedException e) => switch (e.reason) {
    BackupRejection.notABackup => context.l10n.backupNotABackup,
    BackupRejection.tooNew => context.l10n.backupTooNew,
  };

  /// What a database holds, in the same four lines wherever it is shown: on the
  /// way out beside the code, and on the way in beside the question.
  Widget _summaryCard(
    AppLocalizations l,
    BackupInfo info, {
    required String title,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(width: 12),
          // Takes the rest of the row and wraps inside it rather than
          // being pushed past its edge by a Spacer: the device is named
          // here, and a name is as long as the device's owner made it.
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            row(Icons.schedule_rounded, l.backupWhen, _whenOf(l, info)),
            row(
              Icons.smartphone_rounded,
              l.backupDevice,
              info.deviceLabel ?? l.unknownDevice,
            ),
            row(Icons.people_alt_rounded, l.players, '${info.playerCount}'),
            row(
              Icons.sports_esports_rounded,
              l.backupGames,
              '${info.gameCount}',
            ),
            row(Icons.data_usage_rounded, l.backupSize, _sizeOf(info)),
          ],
        ),
      ),
    );
  }

  /// The backup's timestamp, or a stand-in for a file that carries none.
  String _whenOf(AppLocalizations l, BackupInfo info) => info.createdAt == null
      ? l.backupUnknownDate
      : DateFormat('dd.MM.yy  HH:mm').format(info.createdAt!);

  /// The file size, in whichever unit keeps it to a couple of digits.
  String _sizeOf(BackupInfo info) {
    final kb = info.sizeBytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  /// A bordered line of explanation above whatever the mode is showing.
  Widget _note(String text, {bool isError = false}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline_rounded,
              size: 18,
              color: isError ? cs.error : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: isError ? cs.error : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows [message] in a snackbar.
  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}
