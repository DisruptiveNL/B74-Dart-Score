import 'package:dartscore_app/services/device_description.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a device calls itself on the other end of a sync or a restore.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dartscore/device_description');

  /// Answers the channel with [reply], or lets it fail when [reply] is null.
  void mockPlatform(Map<String, String>? reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (reply == null) throw PlatformException(code: 'nope');
          return reply;
        });
  }

  setUp(() => DeviceDescription.debugSetLabel(null));

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    DeviceDescription.debugSetLabel(null);
  });

  group('the label put on anything leaving the device', () {
    test('puts the operating system after the name, in brackets', () async {
      mockPlatform({'name': 'iPhone16,1', 'os': 'iOS 18.5'});

      expect(await DeviceDescription.label, 'iPhone16,1 (iOS 18.5)');
    });

    test('reports what the platform said, without translating it', () async {
      // No table of marketing names in between. iOS reports a model identifier
      // and that is what travels: it is exact and unique per model, where a
      // table would need a line for every phone Apple ships.
      mockPlatform({'name': 'iPhone99,9', 'os': 'iOS 30.0'});

      expect(await DeviceDescription.label, 'iPhone99,9 (iOS 30.0)');
    });

    test('passes an Android name straight through', () async {
      mockPlatform({'name': "Niklas' S23", 'os': 'Android 14'});

      expect(await DeviceDescription.label, "Niklas' S23 (Android 14)");
    });

    test('is resolved once and then kept', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return {'name': 'iPhone16,1', 'os': 'iOS 18.5'};
          });

      await DeviceDescription.label;
      await DeviceDescription.label;

      expect(calls, 1, reason: 'none of what it reads changes while it runs');
    });

    test(
      'falls back to a plain name when the platform cannot answer',
      () async {
        // A transfer must not fail over what it is called, so a channel that is
        // not there is an answer of last resort rather than an exception.
        mockPlatform(null);

        final label = await DeviceDescription.label;
        expect(label, anyOf('iPhone', 'Android'));
      },
    );

    test('falls back when the platform answers with nothing usable', () async {
      mockPlatform({'name': '', 'os': ''});

      final label = await DeviceDescription.label;
      expect(label, anyOf('iPhone', 'Android'));
    });

    test('manages without an operating system rather than showing empty '
        'brackets', () async {
      mockPlatform({'name': 'iPhone16,1'});

      expect(await DeviceDescription.label, 'iPhone16,1');
    });
  });
}
