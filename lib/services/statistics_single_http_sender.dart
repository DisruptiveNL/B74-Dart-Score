import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../database/db_helper.dart';

/// Independent Statistics Library sender. No credentials are stored in SQLite.
/// Not yet wired into the scoring lifecycle or Dashboard synchronization.
class StatisticsSingleHttpSender {
  StatisticsSingleHttpSender({
    DbHelper? database,
    required this.endpoint,
    required this.token,
    HttpClient Function()? clientFactory,
  }) : _database = database ?? DbHelper.instance,
       _clientFactory = clientFactory ?? HttpClient.new;

  final DbHelper _database;
  final Uri? endpoint;
  final String? token;
  final HttpClient Function() _clientFactory;
  bool _running = false;

  /// True only for a correctly configured HTTPS endpoint (HTTP loopback for tests).
  bool get configured {
    final url = endpoint;
    return url != null &&
        url.hasAuthority &&
        (url.scheme == 'https' ||
            (url.scheme == 'http' &&
                (url.host == 'localhost' || url.host == '127.0.0.1'))) &&
        token != null &&
        token!.trim().isNotEmpty;
  }

  /// A failure leaves the row pending. ACK is revision-specific and durable.
  /// Never logs payloads or tokens.
  Future<int> flush() async {
    if (_running || !configured) return 0;
    _running = true;
    var acknowledged = 0;
    try {
      final pending = await _database.pendingStatisticsSingles();
      for (final row in pending) {
        final matchId = row['match_id'] as String;
        final slot = row['slot'] as int;
        final revision = row['revision'] as int;
        final payload = row['payload'] as String;
        try {
          final event = jsonDecode(payload);
          if (event is! Map<String, dynamic> ||
              event['matchId'] != matchId ||
              event['revision'] != revision ||
              event['game'] is! Map ||
              (event['game'] as Map)['slot'] != slot ||
              event['eventType'] != 'SINGLE_PUBLISH') {
            continue;
          }
          final client = _clientFactory();
          try {
            client.connectionTimeout = const Duration(seconds: 5);
            final request = await client
                .postUrl(endpoint!)
                .timeout(const Duration(seconds: 8));
            request.headers.contentType = ContentType.json;
            request.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer $token',
            );
            request.write(payload);
            final response = await request.close().timeout(
              const Duration(seconds: 12),
            );
            final body = await utf8.decoder
                .bind(response)
                .join()
                .timeout(const Duration(seconds: 12));
            if (response.statusCode != 200 && response.statusCode != 201)
              continue;
            final ack = jsonDecode(body);
            if (ack is! Map ||
                ![
                  'SINGLE_PUBLISHED',
                  'ALREADY_PROCESSED',
                ].contains(ack['code']) ||
                ack['eventId'] != event['eventId'] ||
                ack['matchId'] != matchId ||
                ack['slot'] != slot ||
                ack['revision'] != revision) {
              continue;
            }
            if (await _database.acknowledgeStatisticsSingle(
              matchId: matchId,
              slot: slot,
              revision: revision,
            )) {
              acknowledged++;
            }
          } finally {
            client.close(force: true);
          }
        } catch (_) {
          // Offline, timeout, 401, 409, malformed ACK: preserve pending row.
        }
      }
    } finally {
      _running = false;
    }
    return acknowledged;
  }
}
