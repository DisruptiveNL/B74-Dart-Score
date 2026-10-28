import 'package:flutter_test/flutter_test.dart';
import 'package:dartscore_app/services/b74_pairing_record.dart';

void main() {
  final created = DateTime.utc(2026, 10, 28, 10);
  B74PairingRecord record({int hours = 48}) => B74PairingRecord(
    peerId: 'tablet-id',
    createdAtUtc: created,
    expiresAtUtc: created.add(Duration(hours: hours)),
    revoked: false,
  );

  test('valid for less than 48 hours, expired at exactly 48 hours', () {
    expect(record().validAt(created.add(const Duration(hours: 47))), isTrue);
    expect(record().validAt(created.add(const Duration(hours: 48))), isFalse);
  });

  test('rejects a lifetime longer than 48 hours', () {
    expect(record(hours: 49).validAt(created), isFalse);
  });

  test('revocation immediately invalidates pairing', () {
    expect(record().revoke().validAt(created), isFalse);
  });

  test('changing IP does not extend trust', () {
    final changed = record().withAddress('10.0.0.5', 33880);
    expect(changed.expiresAtUtc, record().expiresAtUtc);
    expect(changed.validAt(created.add(const Duration(hours: 48))), isFalse);
    expect(B74PairingRecord.decode(changed.encode()).lastKnownHost, '10.0.0.5');
  });
}
