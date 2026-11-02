import 'dart:convert';

/// C1B9d Admin 2C: separate wire format for exceptional administrator
/// deletion. Parsing a message never authorizes or executes a deletion.
/// Transport authentication, durable authorization, and transactional
/// statistics handling must be implemented before enabling this route.
class B74AdminDeletionWireContract {
  const B74AdminDeletionWireContract._();

  static const type = 'b74.match.admin-deletion.request';
  static const version = 2;

  static Map<String, Object> request({
    required String matchId,
    required int revision,
    required String scope,
    required String statisticsMode,
    required String authorizationId,
  }) {
    if (matchId.isEmpty || matchId.trim() != matchId || revision < 1 ||
        !const {'official', 'historical_development'}.contains(scope) ||
        !const {'retain', 'remove'}.contains(statisticsMode) ||
        authorizationId.isEmpty || authorizationId.trim() != authorizationId) {
      throw const FormatException('Ongeldig beheerdersverwijderverzoek');
    }
    return <String, Object>{
      'type': type,
      'version': version,
      'matchId': matchId,
      'revision': revision,
      'scope': scope,
      'statisticsMode': statisticsMode,
      'authorizationId': authorizationId,
    };
  }

  static String encode(Map<String, Object> request) => jsonEncode(request);

  static Map<String, Object> decode(String payload) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw const FormatException('Ongeldige JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 7 || decoded['type'] != type ||
        decoded['version'] != version || decoded['matchId'] is! String ||
        decoded['revision'] is! int || decoded['scope'] is! String ||
        decoded['statisticsMode'] is! String ||
        decoded['authorizationId'] is! String) {
      throw const FormatException('Ongeldig beheerdersverwijderverzoek');
    }
    return request(
      matchId: decoded['matchId'] as String,
      revision: decoded['revision'] as int,
      scope: decoded['scope'] as String,
      statisticsMode: decoded['statisticsMode'] as String,
      authorizationId: decoded['authorizationId'] as String,
    );
  }
}
