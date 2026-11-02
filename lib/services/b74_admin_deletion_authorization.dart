import 'dart:convert';

import 'b74_admin_deletion_wire_contract.dart';
import 'b74_session_manager.dart';

/// Signed, short-lived admin intent proof, bound to the existing verified
/// pairing key. This is a gate only: PIN verification and explicit operator
/// confirmation must happen BEFORE issue(), on the Dashboard.
///
/// The receiver must verify() BEFORE stageAdminDeletionIntent(). A verified
/// intent does not authorize executing a deletion; execution remains disabled.
class B74AdminDeletionAuthorization {
  const B74AdminDeletionAuthorization._();

  static const maxAge = Duration(minutes: 3);
  static const futureSkew = Duration(seconds: 30);
  static const _role = 'dashboard';
  static const _domain = 'b74-admin-deletion-v1';

  static String _operation(Map<String, Object> request, int issuedAtMs) {
    // The request is validated and reconstructed in a fixed field order.
    return '$_domain\n${jsonEncode(<Object>[request['type']!, request['version']!,
      request['matchId']!, request['revision']!, request['scope']!,
      request['statisticsMode']!, request['authorizationId']!, issuedAtMs])}';
  }

  static Map<String, Object> issue({
    required B74SessionManager session,
    required Map<String, Object> request,
    required bool adminPinVerified,
    required bool explicitFinalConfirmation,
    DateTime? now,
  }) {
    if (!adminPinVerified || !explicitFinalConfirmation) {
      throw StateError('Beheerders-PIN en expliciete bevestiging verplicht');
    }
    final valid = B74AdminDeletionWireContract.decode(jsonEncode(request));
    final issuedAt = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final proof = session.operationProof(_role, _operation(valid, issuedAt));
    if (proof == null) throw StateError('Geen geverifieerde koppelsessie');
    return <String, Object>{'request': valid, 'issuedAtMs': issuedAt,
      'proof': proof};
  }

  static Map<String, Object> verify({
    required B74SessionManager session,
    required Map<String, dynamic> envelope,
    DateTime? now,
  }) {
    if (envelope.length != 3 || envelope['request'] is! Map ||
        envelope['issuedAtMs'] is! int || envelope['proof'] is! String) {
      throw const FormatException('Ongeldige beheerdersautorisatie');
    }
    final request = B74AdminDeletionWireContract.decode(
        jsonEncode(envelope['request']));
    final issuedAt = envelope['issuedAtMs'] as int;
    final current = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    if (issuedAt > current + futureSkew.inMilliseconds ||
        current - issuedAt > maxAge.inMilliseconds) {
      throw StateError('Beheerdersautorisatie verlopen');
    }
    if (!session.verifyOperation(_role, _operation(request, issuedAt),
        envelope['proof'] as String)) {
      throw StateError('Beheerdersautorisatie niet geverifieerd');
    }
    return request;
  }
}
