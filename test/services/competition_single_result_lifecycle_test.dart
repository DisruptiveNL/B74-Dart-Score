import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/competition_single_result_lifecycle.dart';

void main() {
  test('archiveren kan alleen via verzenden', () {
    var status = CompetitionSingleResultStatus.notStarted;
    for (final next in [
      CompetitionSingleResultStatus.inProgress,
      CompetitionSingleResultStatus.completed,
      CompetitionSingleResultStatus.sending,
      CompetitionSingleResultStatus.archived,
    ]) {
      status = CompetitionSingleResultLifecycle.transition(status, next);
    }
    expect(CompetitionSingleResultLifecycle.canEdit(status), isFalse);
    expect(CompetitionSingleResultLifecycle.canSend(status), isFalse);
  });

  test('verzendfout laat opnieuw proberen toe', () {
    expect(CompetitionSingleResultLifecycle.transition(
      CompetitionSingleResultStatus.sending,
      CompetitionSingleResultStatus.completed,
    ), CompetitionSingleResultStatus.completed);
  });

  test('zonder verzendbevestiging geen archivering', () {
    expect(() => CompetitionSingleResultLifecycle.transition(
      CompetitionSingleResultStatus.completed,
      CompetitionSingleResultStatus.archived,
    ), throwsStateError);
  });

  test('archief kan niet meer gewijzigd worden', () {
    expect(() => CompetitionSingleResultLifecycle.transition(
      CompetitionSingleResultStatus.archived,
      CompetitionSingleResultStatus.inProgress,
    ), throwsStateError);
  });

  test('sleutel per wedstrijd en single is stabiel', () {
    expect(CompetitionSingleResultLifecycle.resultKey('match-123', 2),
      'match-123:single:2');
    expect(() => CompetitionSingleResultLifecycle.resultKey('match-123', 5),
      throwsArgumentError);
  });
}
