import 'package:dartscore_app/services/sync_codec.dart';
import 'package:dartscore_app/services/transfer_invite.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a connection QR code carries.
///
/// The format this replaced was three colon-separated fields, which held one
/// address, could not grow, and would have shattered on the first SSID with a
/// colon in it.
void main() {
  TransferInvite invite({
    List<String> addresses = const ['192.168.1.42'],
    HotspotCredentials? hotspot,
    Duration age = Duration.zero,
  }) => TransferInvite(
    addresses: addresses,
    port: 54321,
    token: 'K7M3PQRSTUVWXYZ2',
    hotspot: hotspot,
    expiresAt: DateTime.now().add(kInviteLifetime).subtract(age),
  );

  group('there and back', () {
    test('an ordinary invitation survives the round trip', () {
      final original = invite();
      final read = TransferInvite.parse(
        original.qrPayload(kSyncWifiPrefix),
        prefix: kSyncWifiPrefix,
      );

      expect(read, isNotNull);
      expect(read!.addresses, original.addresses);
      expect(read.port, original.port);
      expect(read.token, original.token);
      expect(read.hotspot, isNull);
      expect(
        read.expiresAt.millisecondsSinceEpoch,
        original.expiresAt.millisecondsSinceEpoch,
      );
    });

    test('several addresses travel in order', () {
      final original = invite(
        addresses: ['192.168.49.1', '192.168.1.42', '10.0.0.7'],
      );
      final read = TransferInvite.parse(
        original.qrPayload(kSyncWifiPrefix),
        prefix: kSyncWifiPrefix,
      );

      expect(read!.addresses, ['192.168.49.1', '192.168.1.42', '10.0.0.7']);
    });

    test('hotspot credentials travel with the endpoint', () {
      // One scan has to both join the network and reach the server on it.
      final original = invite(
        addresses: ['192.168.49.1'],
        hotspot: const HotspotCredentials(
          ssid: 'AndroidShare_4711',
          passphrase: 'k9x:vm/2 Q',
        ),
      );
      final read = TransferInvite.parse(
        original.qrPayload(kSyncWifiPrefix),
        prefix: kSyncWifiPrefix,
      );

      expect(read!.hotspot!.ssid, 'AndroidShare_4711');
      expect(
        read.hotspot!.passphrase,
        'k9x:vm/2 Q',
        reason: 'a colon or a space in the passphrase used to split the code',
      );
    });

    test('the code stays in the QR alphanumeric set', () {
      // Byte mode holds about a third less, and these codes are read across a
      // table in whatever light the room has.
      final payload = invite(
        hotspot: const HotspotCredentials(
          ssid: 'AndroidShare_4711',
          passphrase: 'lower Case+ü',
        ),
      ).qrPayload(kSyncWifiPrefix);

      expect(isAlphanumericSafe(payload), isTrue);
    });
  });

  group('what is refused', () {
    test('a code of the other kind is not read', () {
      final payload = invite().qrPayload(kBackupWifiPrefix);

      expect(
        TransferInvite.parse(payload, prefix: kSyncWifiPrefix),
        isNull,
        reason: 'a backup replaces the device, a sync merges into it',
      );
      expect(
        TransferInvite.parse(payload, prefix: kBackupWifiPrefix),
        isNotNull,
      );
    });

    test('anything else the camera saw is one null', () {
      for (final raw in [
        '',
        'DSW:',
        'DSW:!!!!',
        'https://example.com',
        'DS2:AB',
      ]) {
        expect(
          TransferInvite.parse(raw, prefix: kSyncWifiPrefix),
          isNull,
          reason: 'refused: $raw',
        );
      }
    });

    test('an invitation without an address is not one', () {
      final payload = TransferInvite(
        addresses: const [],
        port: 54321,
        token: 'K7M3PQRSTUVWXYZ2',
        expiresAt: DateTime.now(),
      ).qrPayload(kSyncWifiPrefix);

      expect(TransferInvite.parse(payload, prefix: kSyncWifiPrefix), isNull);
    });
  });

  group('expiry', () {
    test('a fresh invitation is good', () {
      expect(invite().isExpired, isFalse);
    });

    test('an old one is named as expired rather than left to time out', () {
      expect(
        invite(age: kInviteLifetime + const Duration(seconds: 1)).isExpired,
        isTrue,
      );
    });

    test('expiry survives the round trip', () {
      final payload = invite(
        age: kInviteLifetime + const Duration(minutes: 1),
      ).qrPayload(kSyncWifiPrefix);

      expect(
        TransferInvite.parse(payload, prefix: kSyncWifiPrefix)!.isExpired,
        isTrue,
      );
    });
  });

  test('the endpoints are the addresses in order, under the token', () {
    final endpoints = invite(addresses: ['192.168.49.1', '10.0.0.7']).endpoints;

    expect(endpoints.map((e) => e.toString()), [
      'http://192.168.49.1:54321/K7M3PQRSTUVWXYZ2',
      'http://10.0.0.7:54321/K7M3PQRSTUVWXYZ2',
    ]);
  });
}
