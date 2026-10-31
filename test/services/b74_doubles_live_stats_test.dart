import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_live_stats.dart';

void main() {
  test('3-dart average uses checkout dart count', () {
    const stats = B74DoublesPlayerStats([60, 40], [3, 1]);
    expect(stats.dartsThrown, 4);
    expect(stats.threeDartAverage, 75);
    expect(stats.firstNineAverage, isNull);
  });
  test('first nine uses first three full visits', () {
    const stats = B74DoublesPlayerStats([60, 100, 80, 140], [3, 3, 3, 3]);
    expect(stats.firstNineAverage, 80);
    expect(stats.threeDartAverage, 95);
  });
}
