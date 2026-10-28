import 'package:dartscore_app/widgets/wifi_pairing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

/// The dialog that asks the sending device to let a waiting peer in. Both the
/// profile sync and the database transfer put this same one up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Records the haptics the dialog asks the platform for.
  List<String> watchHaptics() {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            calls.add('${call.arguments}');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return calls;
  }

  testWidgets('buzzes once when it appears', (tester) async {
    // It arrives while the user is looking at the other device, so without a
    // nudge the pairing waits until somebody happens to glance back.
    final haptics = watchHaptics();

    await tester.pumpWidget(testApp(const PairingDialog(pin: '1234')));
    await tester.pumpAndSettle();

    expect(haptics, hasLength(1));
    // The impact taps travel as an argument naming which one; the plain,
    // strongest vibrate carries none. Anything else here means it was quietly
    // softened back to a tap.
    expect(
      haptics.single,
      'null',
      reason: 'the full vibrate, so it carries like a notification',
    );
  });

  testWidgets('does not buzz again on a rebuild', (tester) async {
    final haptics = watchHaptics();

    await tester.pumpWidget(testApp(const PairingDialog(pin: '1234')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(testApp(const PairingDialog(pin: '1234')));
    await tester.pumpAndSettle();

    expect(haptics, hasLength(1));
  });

  testWidgets('shows the number the other device is showing', (tester) async {
    watchHaptics();

    await tester.pumpWidget(testApp(const PairingDialog(pin: '4821')));
    await tester.pumpAndSettle();

    expect(find.text('4821'), findsOneWidget);
  });
}
