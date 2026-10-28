import 'dart:convert';
import 'dart:typed_data';

import 'package:dartscore_app/services/sync_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The size limits the transport choice works from are only real if the codes
/// actually render at the version they were sized for. These tests build the
/// codes the sender would show, because the failure otherwise appears on a
/// phone screen as a blank box and nowhere else.
void main() {
  /// A payload of exactly [chars] characters from the base45 alphabet.
  String payloadOf(int chars) => 'DS2:${'W' * (chars - 4)}';

  /// Frames as the sender really produces them, over a payload large enough to
  /// need many blocks.
  SyncFountainEncoder encoder() => SyncFountainEncoder(
    Uint8List.fromList(List.generate(60000, (i) => (i * 37 + 11) % 256)),
  );

  group('rendering sync codes', () {
    test('a full frame stays inside version 15', () {
      final frame = encoder().frameAt(0);
      expect(frame.length, lessThanOrEqualTo(kFrameMaxChars));

      final qr = buildQrCode(frame);
      expect(
        qr.typeNumber,
        lessThanOrEqualTo(15),
        reason: 'a denser code than this stalls while it is moving',
      );
      expect(qr.errorCorrectLevel, QrErrorCorrectLevel.M);
    });

    test('frames all resolve to the same version', () {
      // What lets the version be resolved once per transfer instead of once
      // per shown frame, which at ten frames a second is the difference
      // between one QR code built and fifteen thrown away. Frames only share a
      // length while the seed does, so the check spans a seed getting longer.
      final source = encoder();
      final versions = {
        for (final index in [0, 1, 40, 1000, 50000])
          buildQrCode(source.frameAt(index)).typeNumber,
      };

      expect(versions, hasLength(1));
    });

    test('the largest static payload still renders', () {
      final qr = buildQrCode(payloadOf(kStaticQrMaxChars));
      expect(qr.typeNumber, lessThanOrEqualTo(40));
    });

    test('a payload uses fewer modules than the same data in byte mode', () {
      final data = payloadOf(2000);

      final alphanumeric = buildQrCode(data);
      final byteMode = () {
        for (var version = 1; version <= 40; version++) {
          final qr = QrCode(version, QrErrorCorrectLevel.M)..addData(data);
          try {
            QrImage(qr);
            return qr;
          } on InputTooLongException {
            continue;
          }
        }
        fail('byte mode should still fit');
      }();

      expect(
        alphanumeric.typeNumber,
        lessThan(byteMode.typeNumber),
        reason: 'the dense mode is the whole point of base45',
      );
    });

    test('the Wi-Fi connection code falls back to the byte mode', () {
      // Lower case and braces put this outside the alphanumeric set.
      final data = jsonEncode({'ip': '192.168.1.42', 'port': 54321});
      expect(isAlphanumericSafe(data), isFalse);
      expect(() => buildQrCode(data), returnsNormally);
    });

    test('a payload at the static limit renders', () {
      // The case that used to fail silently, when the limit was computed for a
      // different error correction level than the one being rendered.
      expect(() => buildQrCode(payloadOf(kStaticQrMaxChars)), returnsNormally);
    });
  });
}
