import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the camera plugin, so a screen that shows its scanner can be pumped.
///
/// The receive halves of sync and backup put the camera on screen as soon as
/// they open, which means every widget test that reaches them builds
/// `MobileScanner`. Without this the plugin's first call fails with a missing
/// implementation and the screen renders an error placeholder instead of the
/// thing under test.
///
/// It answers rather than pretends to scan: nothing here produces a barcode.
/// What a scan leads to is exercised through the codec and the transport,
/// which take a payload as a string and need no camera at all.
void useFakeScanner() {
  const methodChannel = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );
  const eventChannel = EventChannel(
    'dev.steenbakker.mobile_scanner/scanner/event',
  );
  const orientationChannel = EventChannel(
    'dev.steenbakker.mobile_scanner/scanner/deviceOrientation',
  );

  // Read inside the callbacks, not here: this runs while the group is being
  // declared, and the binding does not exist yet at that point.
  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger().setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        // Already authorized, so nothing asks the user for anything.
        case 'state':
          return 1;
        case 'request':
          return true;
        case 'start':
          // Every key the platform channel reads on the way back, the Android
          // specific ones included: the test binding reports Android unless a
          // test says otherwise, and a missing key there is an exception
          // rather than a default.
          return <String, Object?>{
            'textureId': 1,
            'size': <String, Object?>{'width': 640.0, 'height': 480.0},
            'currentTorchState': 0,
            'numberOfCameras': 1,
            'cameraDirection': 1,
            'handlesCropAndRotation': true,
            'naturalDeviceOrientation': 'PORTRAIT_UP',
            'sensorOrientation': 90,
          };
        case 'getSupportedLenses':
          return <int>[1];
        default:
          return null;
      }
    });

    for (final channel in [eventChannel, orientationChannel]) {
      messenger().setMockStreamHandler(channel, _SilentStream());
    }
  });

  tearDown(() {
    messenger().setMockMethodCallHandler(methodChannel, null);
    for (final channel in [eventChannel, orientationChannel]) {
      messenger().setMockStreamHandler(channel, null);
    }
  });
}

/// An event channel that accepts a listener and never sends anything.
class _SilentStream extends MockStreamHandler {
  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {}

  @override
  void onCancel(Object? arguments) {}
}
