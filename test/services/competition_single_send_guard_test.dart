import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_single_send_guard.dart';

void main() {
  test('archived is acknowledged and never sent again', () {
    expect(CompetitionSingleSendGuard.evaluate('archived'),
        CompetitionSingleSendAction.alreadyArchived);
  });
  test('sending is not an acknowledgement and must not be duplicated', () {
    expect(CompetitionSingleSendGuard.evaluate('sending'),
        CompetitionSingleSendAction.inProgress);
  });
  test('completed remains retryable after a transport failure', () {
    expect(CompetitionSingleSendGuard.evaluate('completed'),
        CompetitionSingleSendAction.send);
  });
  test('missing result is not incorrectly considered acknowledged', () {
    expect(CompetitionSingleSendGuard.evaluate(null),
        CompetitionSingleSendAction.send);
  });
}
