import 'dart:convert';
import 'dart:io';

import 'package:dartscore_app/database/db_helper.dart';
import 'package:dartscore_app/services/statistics_single_http_sender.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  late HttpServer server;
  final db = DbHelper.instance;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('b74_stats_http_');
    await DbHelper.debugReset();
    DbHelper.debugDatabasePath = '${directory.path}/dartscore.db';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    await DbHelper.debugReset();
    DbHelper.debugDatabasePath = null;
    await directory.delete(recursive: true);
  });

  Future<void> queue() => db.enqueueStatisticsSingle(
    matchId: 'm1',
    slot: 1,
    revision: 1,
    payload: jsonEncode({
      'eventType': 'SINGLE_PUBLISH',
      'eventId': 'e1',
      'matchId': 'm1',
      'revision': 1,
      'game': {'slot': 1},
    }),
  );

  Uri url() =>
      Uri.parse('http://127.0.0.1:${server.port}/api/v1/singles/publish');

  test('missing configuration keeps pending without network', () async {
    await queue();
    final sender = StatisticsSingleHttpSender(endpoint: null, token: null);
    expect(await sender.flush(), 0);
    expect(await db.pendingStatisticsSingles(), hasLength(1));
  });

  test('successful exact ACK persists across database reopen', () async {
    await queue();
    final responding = server.first.then((request) async {
      expect(request.uri.path, '/api/v1/singles/publish');
      expect(request.headers.value('authorization'), 'Bearer test-token');
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.statusCode = 201;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 'SINGLE_PUBLISHED',
          'eventId': payload['eventId'],
          'matchId': payload['matchId'],
          'slot': 1,
          'revision': 1,
        }),
      );
      await request.response.close();
    });

    final sender = StatisticsSingleHttpSender(
      endpoint: url(),
      token: 'test-token',
    );
    expect(await sender.flush(), 1);
    await responding;
    await DbHelper.debugReset();
    expect(await db.pendingStatisticsSingles(), isEmpty);
    expect(await sender.flush(), 0);
  });

  test('wrong ACK never acknowledges', () async {
    await queue();
    final responding = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response.statusCode = 201;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 'SINGLE_PUBLISHED',
          'eventId': 'wrong',
          'matchId': 'm1',
          'slot': 1,
          'revision': 1,
        }),
      );
      await request.response.close();
    });

    expect(
      await StatisticsSingleHttpSender(
        endpoint: url(),
        token: 'test-token',
      ).flush(),
      0,
    );
    await responding;
    expect(await db.pendingStatisticsSingles(), hasLength(1));
  });

  test('401 unauthorized leaves row pending', () async {
    await queue();
    final responding = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response.statusCode = 401;
      request.response.write('{"code":"UNAUTHORIZED"}');
      await request.response.close();
    });

    expect(
      await StatisticsSingleHttpSender(endpoint: url(), token: 'wrong').flush(),
      0,
    );
    await responding;
    expect(await db.pendingStatisticsSingles(), hasLength(1));
  });

  test('remote HTTPS is required; arbitrary HTTP is rejected', () async {
    await queue();
    final sender = StatisticsSingleHttpSender(
      endpoint: Uri.parse('http://example.com/api/v1/singles/publish'),
      token: 'test',
    );
    expect(sender.configured, isFalse);
    expect(await sender.flush(), 0);
  });
}
