import 'package:dartscore_app/services/local_addresses.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which address a connection code names.
///
/// The lookup this replaced preferred interfaces called `en*`, a name no
/// Android device has, and then fell back to whatever the system listed first.
/// That is how a code came to carry a mobile data address: it scanned, it
/// parsed, and it could never connect.
void main() {
  /// One interface for the ranking to look at.
  LocalInterface iface(String name, List<String> addresses) =>
      (name: name, addresses: addresses);

  group('what is offered', () {
    test('Android Wi-Fi is taken and mobile data is not', () {
      final ranked = rankTransferAddresses([
        iface('rmnet_data0', ['10.183.44.7']),
        iface('wlan0', ['192.168.1.42']),
        iface('lo', ['127.0.0.1']),
      ]);

      expect(ranked, ['192.168.1.42']);
    });

    test('a VPN tunnel is not offered, private range or not', () {
      // The address range check alone would let this through: a VPN hands out
      // addresses from exactly the same ranges as a router.
      final ranked = rankTransferAddresses([
        iface('utun3', ['10.8.0.6']),
        iface('en0', ['192.168.178.25']),
      ]);

      expect(ranked, ['192.168.178.25']);
    });

    test('an interface nobody listed is dropped rather than ranked last', () {
      final ranked = rankTransferAddresses([
        iface('something0', ['192.168.5.5']),
      ]);

      expect(ranked, isEmpty);
    });

    test('a public address is not a local one', () {
      final ranked = rankTransferAddresses([
        iface('en0', ['93.184.216.34']),
      ]);

      expect(ranked, isEmpty);
    });

    test('the carrier range only looks private', () {
      final ranked = rankTransferAddresses([
        iface('wlan0', ['100.87.3.9']),
      ]);

      expect(ranked, isEmpty);
    });
  });

  group('what comes first', () {
    test('a hotspot subnet outranks the router', () {
      final ranked = rankTransferAddresses([
        iface('wlan0', ['192.168.1.42']),
        iface('ap0', ['192.168.49.1']),
      ]);

      expect(
        ranked.first,
        '192.168.49.1',
        reason: 'nothing sits between two devices on a phone-raised network',
      );
      expect(ranked, ['192.168.49.1', '192.168.1.42']);
    });

    test('the iOS hotspot subnet counts too', () {
      final ranked = rankTransferAddresses([
        iface('en0', ['172.20.10.3']),
      ]);

      expect(ranked, ['172.20.10.3']);
    });

    test('no more candidates than a code carries', () {
      final ranked = rankTransferAddresses([
        iface('wlan0', ['192.168.1.1', '192.168.1.2']),
        iface('en0', ['10.0.0.1', '10.0.0.2']),
      ]);

      expect(ranked, hasLength(kMaxTransferAddresses));
    });

    test('the same address on two interfaces is offered once', () {
      final ranked = rankTransferAddresses([
        iface('wlan0', ['192.168.1.42']),
        iface('bridge0', ['192.168.1.42']),
      ]);

      expect(ranked, ['192.168.1.42']);
    });
  });

  test('a device on no network offers nothing rather than loopback', () {
    // The fallback that used to sit here produced `127.0.0.1`, which is a
    // connection code that looks entirely valid and reaches only itself.
    expect(
      rankTransferAddresses([
        iface('lo', ['127.0.0.1']),
      ]),
      isEmpty,
    );
  });
}
