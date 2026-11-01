import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_result_contract.dart';

void main() {
  test('doubles result identity remains stable across retries', () {
    expect(B74DoublesResultContract.resultId('match-1', 2),
        B74DoublesResultContract.resultId('match-1', 2));
    expect(B74DoublesResultContract.resultId('match-1', 2),
        isNot(B74DoublesResultContract.resultId('match-1', 3)));
  });
}
