import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/local_hotspot.dart';
import '../services/sync_codec.dart' show buildQrCode, kScannerDetectionTimeout;
import '../services/sync_service.dart';
import '../utils/layout.dart';

/// The parts a device-to-device transfer shows on screen, shared by the profile
/// sync and by handing the whole database over.
///
/// Both pair the same way: one device shows a code, the other reads it, and the
/// four digits they then both display are what tells the user that the device
/// asking is the one in front of them. Only what travels afterwards differs, so
/// only that lives in the screens.

/// Camera QR scanner that reports every decoded payload via a callback.
///
/// It keeps reporting rather than stopping after the first hit, because an
/// animated transfer arrives as a long series of codes. Deciding when enough
/// has been read is the caller's job.
class QrScanner extends StatefulWidget {
  final void Function(String) onScanned;
  const QrScanner({super.key, required this.onScanned});

  @override
  State<QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<QrScanner> with WidgetsBindingObserver {
  /// The last payload handed on, so the same code sitting in front of the
  /// camera is not reported dozens of times a second.
  String? _lastReported;

  /// The scanner is throttled far below its default, because an animated
  /// transfer is a race between how fast the sender shows frames and how often
  /// the camera is allowed to report one. At the default of 250ms both run at
  /// the same rate, and two free running clocks of the same rate drift against
  /// each other, so a good share of the frames is never sampled. Keeping the
  /// throttle rather than removing it altogether bounds the work per second,
  /// which [DetectionSpeed.unrestricted] explicitly does not.
  late final MobileScannerController _controller = MobileScannerController(
    detectionTimeoutMs: kScannerDetectionTimeout.inMilliseconds,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// Shuts the camera down while the app is away and brings it back on return.
  ///
  /// [MobileScanner] only manages this itself when it creates its own
  /// controller; passing one in, as these screens do for the detection
  /// throttle, hands the job over. Without it the camera goes on running and
  /// decoding in the background, which is both the most expensive thing the
  /// screen does and a light the user did not ask to leave on.
  ///
  /// The states mirror what the package does with its own controller:
  /// `inactive` already precedes `paused` and `hidden` on both platforms, so
  /// stopping there covers all three, and the permission check keeps a resume
  /// from starting a camera the user has not granted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.inactive:
        unawaited(_controller.stop());
      case AppLifecycleState.resumed:
        unawaited(_controller.start());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final raw = capture.barcodes.firstOrNull?.rawValue;
              if (raw == null || raw == _lastReported) return;
              _lastReported = raw;
              widget.onScanned(raw);
            },
          ),
          // The frame follows the picture: on a tablet the camera fills far
          // more than the 200 dp square a phone was drawn.
          LayoutBuilder(
            builder: (context, box) {
              final side = (box.biggest.shortestSide * 0.6)
                  .clamp(160.0, 420.0)
                  .toDouble();
              return Center(
                child: Container(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.primary, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Text(
              context.l10n.qrScanHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks the sending device to let a waiting peer in, showing the number both
/// screens are displaying.
///
/// The number is what tells the user that the device asking is the one in front
/// of them. The token in the connection code is what actually keeps everyone
/// else out; this is the part the user can see.
///
/// Opening vibrates once, like a notification. This dialog is the one moment in
/// a transfer that waits on the user, and it arrives while they are looking at
/// the other device, so without a nudge the pairing sits there until somebody
/// happens to glance back.
class PairingDialog extends StatefulWidget {
  final String pin;

  const PairingDialog({super.key, required this.pin});

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  @override
  void initState() {
    super.initState();
    // The full vibrate rather than one of the impact taps, so it carries like
    // a notification: the user is holding the other device when this arrives
    // and a tap is easy to miss. This is the strongest haptic available
    // without the VIBRATE permission and the vibrator API behind it, and it is
    // silently ignored where the hardware has none.
    HapticFeedback.vibrate();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    return PopScope(
      canPop: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
          child: AlertDialog(
            title: Text(l.syncPairTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.syncPairBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Text(
                  widget.pin,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.syncReject),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.syncApprove),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The white card every QR code sits on, with [title] above it.
///
/// The code fills the available width instead of a fixed size, so a dense
/// payload still renders modules large enough for another phone to read.
class PairingQrCard extends StatelessWidget {
  final String data;
  final String? title;

  const PairingQrCard({super.key, required this.data, this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          // Square, and never so tall that what belongs under it is pushed off
          // the screen. Measured against the window rather than the box,
          // because in a scrolling column there is no height to measure.
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).height * 0.5,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView.withQr(
            qr: buildQrCode(data),
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFFB71C1C),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which way the two devices reach each other.
enum TransferRoute {
  /// A Wi-Fi both are already on.
  sharedWifi,

  /// A network this device raises for the length of the transfer.
  ownNetwork,
}

/// The choice between the two routes, above the button that starts a transfer.
///
/// [ownNetworkAvailable] is false on every device that cannot raise a network,
/// which is every iPhone and every Android below 13. The row is then gone
/// rather than disabled: an option that can never be picked on this device is
/// not a choice, and explaining why would say more about Android versions than
/// anyone wants to read while sending a profile.
class TransferRouteSelector extends StatelessWidget {
  final TransferRoute value;
  final ValueChanged<TransferRoute> onChanged;
  final bool ownNetworkAvailable;
  final bool enabled;

  /// What to say instead, when this device cannot raise a network at all.
  ///
  /// Only worth a sentence where the user is otherwise stuck: iOS lets no app
  /// raise a hotspot, so somebody with no shared Wi-Fi needs to be pointed at
  /// the routes that are left. An Android too old for it says nothing extra,
  /// because the answer there is a Wi-Fi and that is already on screen.
  final String? unavailableHint;

  const TransferRouteSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.ownNetworkAvailable,
    this.enabled = true,
    this.unavailableHint,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;

    // Nothing to choose between. The hint that used to stand here says the same
    // thing the one remaining option would.
    if (!ownNetworkAvailable) {
      final hint = unavailableHint;
      return Text(
        hint == null
            ? l.routeSharedWifiHint
            : '${l.routeSharedWifiHint}\n$hint',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RadioGroup<TransferRoute>(
        groupValue: value,
        onChanged: (picked) {
          if (picked != null) onChanged(picked);
        },
        child: Column(
          children: [
            _option(
              context,
              TransferRoute.sharedWifi,
              Icons.wifi,
              l.routeSharedWifi,
              l.routeSharedWifiHint,
            ),
            Divider(height: 1, color: cs.outlineVariant),
            _option(
              context,
              TransferRoute.ownNetwork,
              Icons.wifi_tethering,
              l.routeOwnNetwork,
              l.routeOwnNetworkHint,
            ),
          ],
        ),
      ),
    );
  }

  /// One route as a tappable row.
  Widget _option(
    BuildContext context,
    TransferRoute route,
    IconData icon,
    String title,
    String hint,
  ) {
    return RadioListTile<TransferRoute>(
      value: route,
      // Off while a transfer is running: the route cannot change under a
      // server that is already up.
      enabled: enabled,
      controlAffinity: ListTileControlAffinity.leading,
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(hint, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// What to put on screen when a transfer would not start.
///
/// Shared by both screens because there is only one right answer per failure
/// and two copies of this list is how they would start disagreeing. Each of
/// these is a different thing for the user to do, which is the whole reason the
/// failures are told apart in the first place: a running tethering hotspot is
/// theirs to switch off, a refused permission is a dialog to open again, and no
/// Wi-Fi at all is neither.
String transferStartMessage(BuildContext context, Object error) {
  final l = context.l10n;
  return switch (error) {
    TransferStartException(reason: TransferStartFailure.noLocalAddress) =>
      l.syncNoWifiAddress,
    TransferStartException() => l.syncServerFailed,
    HotspotException(reason: HotspotFailure.incompatibleMode) =>
      l.hotspotIncompatible,
    HotspotException(reason: HotspotFailure.permissionDenied) =>
      l.hotspotDenied,
    HotspotException() => l.hotspotFailed,
    _ => '${l.syncServerFailed}\n\n${l.error}: $error',
  };
}
