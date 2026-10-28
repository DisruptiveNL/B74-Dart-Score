import 'dart:io';

import 'package:flutter/material.dart';
import '../widgets/b74_link_indicator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/b74_pairing_security.dart';

import '../services/competition_sync_receiver.dart';

/// Temporary, explicitly approved local network pairing for match imports.
class CompetitionReceiveScreen extends StatefulWidget {
  const CompetitionReceiveScreen({super.key});

  @override
  State<CompetitionReceiveScreen> createState() =>
      _CompetitionReceiveScreenState();
}

class _CompetitionReceiveScreenState extends State<CompetitionReceiveScreen> {
  // One receiver per running app process; navigation must not close its socket.
  static final CompetitionSyncReceiver _appReceiver = CompetitionSyncReceiver();
  CompetitionSyncReceiver get _receiver => _appReceiver;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _running = _receiver.port != null;
    _approved = _receiver.isApproved;
    if (_running) _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4, includeLoopback: false);
    if (!mounted) return;
    setState(() => _addresses = interfaces
      .expand((i) => i.addresses.map((a) => a.address)).toList());
  }
  bool _approved = false;
  bool _busy = false;
  String? _error;
  List<String> _addresses = [];
  B74PairingChallenge? _challenge;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _receiver.start();
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      if (!mounted) return;
      setState(() {
        _addresses = interfaces
            .expand((i) => i.addresses.map((a) => a.address))
            .toList();
        _running = true;
        _approved = false;
        _challenge = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _receiver.stop();
      if (mounted) {
        setState(() {
          _running = false;
          _approved = false;
          _addresses = [];
          _challenge = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Wedstrijden ontvangen'),
      actions: const [B74LinkIndicator()],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Wedstrijdontvanger voor Competition Dashboard',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Gebruik hetzelfde vertrouwde lokale netwerk. '
          'Start de ontvanger en schakel ontvangst expliciet in.',
        ),
        const SizedBox(height: 16),
        Text(_running ? 'Ontvanger actief' : 'Ontvanger uitgeschakeld'),
        if (_running) ...[
          SelectableText('IP-adres(sen): ${_addresses.join(", ")}'),
          SelectableText('Poort: ${_receiver.port}'),
          const Text('Handmatige koppeltokens zijn verborgen.'),
          const SizedBox(height: 16),
          const Text(
            'Beveiligde QR-koppeling',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Scan deze QR-code met Dashboard om de apparaten beveiligd te koppelen.',
          ),
          if (_challenge != null && _challenge!.validAt(DateTime.now().toUtc()))
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: _challenge!.encode(), size: 240),
              ),
            ),
          FilledButton.tonalIcon(
            onPressed: _addresses.isEmpty
                ? null
                : () {
                    final address = _addresses.first;
                    final port = _receiver.port;

                    if (port == null) {
                      return;
                    }

                    final challenge = B74PairingChallenge.generate(
                      deviceId: 'b74-dart-score',
                      host: address,
                      port: port,
                    );
                    _receiver.setProbeChallenge(challenge);
                    setState(() => _challenge = challenge);
                  },
            icon: const Icon(Icons.qr_code),
            label: const Text('Nieuwe QR-code (2 minuten)'),
          ),
          SwitchListTile(
            title: const Text('Ontvangst toestaan'),
            value: _approved,
            onChanged: _busy
                ? null
                : (value) {
                    if (value) {
                      _receiver.approve();
                    } else {
                      _receiver.reject();
                    }
                    setState(() => _approved = value);
                  },
          ),
        ],
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : (_running ? _stop : _start),
          icon: Icon(_running ? Icons.stop : Icons.play_arrow),
          label: Text(_running ? 'Ontvanger stoppen' : 'Ontvanger starten'),
        ),
        const SizedBox(height: 12),
        const Text(
          'De ontvanger blijft actief wanneer je naar een ander scherm gaat. '
          'Gebruik Ontvanger stoppen om hem expliciet uit te schakelen.',
        ),
      ],
    ),
  );
}
