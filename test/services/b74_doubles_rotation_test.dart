import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_doubles_rotation.dart';

void main() {
  test('away starts: teams alternate and each team rotates its two players', () {
    final visits = List.generate(8, (i) =>
        B74DoublesRotation.visit(starterTeam: 1, turnIndex: i));
    expect(visits, [
      (team: 1, player: 0), (team: 0, player: 0),
      (team: 1, player: 1), (team: 0, player: 1),
      (team: 1, player: 0), (team: 0, player: 0),
      (team: 1, player: 1), (team: 0, player: 1),
    ]);
  });

  test('home starts: same captain-supplied player order', () {
    expect(B74DoublesRotation.visit(starterTeam: 0, turnIndex: 0),
        (team: 0, player: 0));
    expect(B74DoublesRotation.visit(starterTeam: 0, turnIndex: 2),
        (team: 0, player: 1));
    expect(B74DoublesRotation.visit(starterTeam: 0, turnIndex: 3),
        (team: 1, player: 1));
  });

  test('new leg resets player positions, respecting bull-selected team', () {
    expect(B74DoublesRotation.firstVisit(0), (team: 0, player: 0));
    expect(B74DoublesRotation.firstVisit(1), (team: 1, player: 0));
  });

  test('invalid team and visit index are rejected', () {
    expect(() => B74DoublesRotation.visit(starterTeam: 2, turnIndex: 0),
        throwsArgumentError);
    expect(() => B74DoublesRotation.visit(starterTeam: 0, turnIndex: -1),
        throwsArgumentError);
  });
}
