import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/b74_team_revision_policy.dart';

void main() {
  B74TeamRevisionDecision check({
    required int revision,
    required String payload,
    int? oldRevision,
    String? oldPayload,
    bool started = false,
  }) => B74TeamRevisionPolicy.decide(
    incomingRevision: revision,
    incomingPayload: payload,
    storedRevision: oldRevision,
    storedPayload: oldPayload,
    hasStarted: started,
  );

  test('eerste revisie maakt wedstrijd aan', () {
    expect(check(revision: 1, payload: 'v1'), B74TeamRevisionDecision.create);
  });
  test('replay van identieke revisie is idempotent', () {
    expect(check(revision: 1, payload: 'v1', oldRevision: 1, oldPayload: 'v1'),
        B74TeamRevisionDecision.unchanged);
  });
  test('gelijke revisie met andere inhoud wordt geweigerd', () {
    expect(check(revision: 1, payload: 'gewijzigd', oldRevision: 1, oldPayload: 'v1'),
        B74TeamRevisionDecision.reject);
  });
  test('opeenvolgende revisie mag voor start', () {
    expect(check(revision: 2, payload: 'v2', oldRevision: 1, oldPayload: 'v1'),
        B74TeamRevisionDecision.replace);
  });
  test('correctie na start wordt geweigerd', () {
    expect(check(revision: 2, payload: 'v2', oldRevision: 1, oldPayload: 'v1', started: true),
        B74TeamRevisionDecision.reject);
  });
  test('verouderde revisie wordt geweigerd', () {
    expect(check(revision: 1, payload: 'v1', oldRevision: 2, oldPayload: 'v2'),
        B74TeamRevisionDecision.reject);
  });
  test('overgeslagen revisie wordt geweigerd', () {
    expect(check(revision: 3, payload: 'v3', oldRevision: 1, oldPayload: 'v1'),
        B74TeamRevisionDecision.reject);
  });
  test('nieuwe wedstrijd mag niet starten met revisie 2', () {
    expect(check(revision: 2, payload: 'v2'), B74TeamRevisionDecision.reject);
  });
  test('replay van gestarte wedstrijd blijft idempotent', () {
    expect(check(revision: 1, payload: 'v1', oldRevision: 1, oldPayload: 'v1', started: true),
        B74TeamRevisionDecision.unchanged);
  });
  test('ongeldige payload of revisie wordt geweigerd', () {
    expect(check(revision: 0, payload: 'v0'), B74TeamRevisionDecision.reject);
    expect(check(revision: 1, payload: ''), B74TeamRevisionDecision.reject);
  });
}
