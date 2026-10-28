import 'dart:async';

import 'package:flutter/services.dart';

import 'transfer_invite.dart';

export 'transfer_invite.dart' show HotspotCredentials;

// ── Failures ──────────────────────────────────────────────────────────────────

/// Why a transfer network could not be raised or joined.
///
/// Told apart because they are answered differently. `incompatibleMode` is the
/// one the user can clear themselves, by turning the ordinary tethering hotspot
/// off; `permissionDenied` is a dialog to open again; the rest are the device
/// saying no.
enum HotspotFailure {
  /// The device or its Android version cannot do this at all.
  unsupported,

  /// The nearby devices permission was refused.
  permissionDenied,

  /// The ordinary tethering hotspot is running, and the two cannot share the
  /// radio.
  incompatibleMode,

  /// The device is not allowed to share a network, usually by a work profile
  /// policy.
  tetheringDisallowed,

  /// No radio channel was free.
  noChannel,

  /// The network was not joined: the user declined the system dialog, or it was
  /// gone by the time this device looked.
  joinFailed,

  /// Anything the platform did not name.
  failed,
}

/// Raised by [LocalHotspot] and [WifiJoin].
class HotspotException implements Exception {
  const HotspotException(this.reason);

  final HotspotFailure reason;

  @override
  String toString() => 'The transfer network failed: ${reason.name}';
}

/// Maps a platform error code onto a [HotspotFailure].
HotspotFailure _failureFrom(Object error) {
  if (error is! PlatformException) return HotspotFailure.failed;
  return switch (error.code) {
    'unsupported' => HotspotFailure.unsupported,
    'permission_denied' => HotspotFailure.permissionDenied,
    'incompatible_mode' => HotspotFailure.incompatibleMode,
    'tethering_disallowed' => HotspotFailure.tetheringDisallowed,
    'no_channel' => HotspotFailure.noChannel,
    'join_failed' => HotspotFailure.joinFailed,
    _ => HotspotFailure.failed,
  };
}

// ── Hosting ───────────────────────────────────────────────────────────────────

/// A Wi-Fi network this device raises for the length of one transfer.
///
/// The transfer that has no shared Wi-Fi to run over, and the one whose router
/// refuses to let two devices reach each other, are the same problem seen twice.
/// A network with nothing on it but the two phones has neither.
///
/// **Android only.** Apple gives no app a way to raise a network:
/// `NEHotspotConfigurationManager` joins existing ones and cannot create one, so
/// [isSupported] is always false on iOS and an iPhone is always the device that
/// joins. Which device hosts says nothing about which way the data travels: an
/// Android phone can raise the network and still be the one receiving.
class LocalHotspot {
  static const MethodChannel _channel = MethodChannel(
    'dartscore/local_hotspot',
  );

  static final StreamController<void> _stopped =
      StreamController<void>.broadcast();

  static bool _listening = false;

  /// Fires when the system took the network down on its own, most often because
  /// Wi-Fi was switched off. Without it a screen waits on a network that is
  /// already gone.
  static Stream<void> get onStopped {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'stopped') _stopped.add(null);
      });
    }
    return _stopped.stream;
  }

  /// Whether this device can raise a transfer network.
  ///
  /// False on iOS, and false below Android 13: the same APIs there want the
  /// location permission and the location switch, which is more than this is
  /// worth asking for. Those devices use the transfer over a shared Wi-Fi.
  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Raises the network and returns what a peer needs to join it.
  ///
  /// The SSID and the passphrase are the system's own and cannot be chosen. It
  /// costs nothing: nobody types them, they travel inside the QR code.
  static Future<HotspotCredentials> start() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, String>('start') ?? const {};
      final ssid = result['ssid'];
      final passphrase = result['passphrase'];
      if (ssid == null || passphrase == null) {
        throw const HotspotException(HotspotFailure.failed);
      }
      return HotspotCredentials(ssid: ssid, passphrase: passphrase);
    } on PlatformException catch (e) {
      throw HotspotException(_failureFrom(e));
    }
  }

  /// Takes the network down. Safe to call when none is up, and has to run on
  /// every way out of a transfer: a hotspot left standing costs battery and
  /// sits in everyone's Wi-Fi list.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // Nothing useful to do about it, and nothing depends on the answer.
    }
  }
}

// ── Joining ───────────────────────────────────────────────────────────────────

/// Joins the network another device raised, from inside the app.
///
/// Both platforms show a system dialog and neither hands the app the Wi-Fi
/// password of anything it did not already have. On Android the join also binds
/// this app's traffic to the joined network, which is not a detail: a transfer
/// network carries no internet, so without the binding Android keeps sending
/// everything over mobile data and the sockets never reach the phone two feet
/// away.
class WifiJoin {
  static const MethodChannel _channel = MethodChannel('dartscore/wifi_join');

  /// Whether this device can join from inside the app.
  ///
  /// When false the user still has a way in: the credentials are shown, and
  /// they pick the network in the system settings themselves.
  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Joins the network [credentials] describes, and returns once it is up.
  static Future<void> join(HotspotCredentials credentials) async {
    try {
      await _channel.invokeMethod<void>('join', {
        'ssid': credentials.ssid,
        'passphrase': credentials.passphrase,
      });
    } on PlatformException catch (e) {
      throw HotspotException(_failureFrom(e));
    }
  }

  /// Leaves the network and puts this app's traffic back on the ordinary route.
  ///
  /// Has to run on every way out, the failures included. An app still bound to
  /// a network that is gone has no route to anything at all.
  static Future<void> leave() async {
    try {
      await _channel.invokeMethod<void>('leave');
    } catch (_) {
      // Same as [LocalHotspot.stop]: nothing depends on the answer.
    }
  }
}
