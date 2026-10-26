import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartscore_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Wi-Fi transfer opens a socket on the local network and hands over a
/// player's whole history, so who gets an answer out of it is the one thing
/// here worth pinning down. These tests drive the real server over real HTTP.
void main() {
  late SyncServer server;
  late TransferInvite connection;

  const payload = 'DS2:PAYLOAD';

  /// Reaches the server on loopback, whatever address it reported.
  TransferInvite loopback(String token) => TransferInvite.forNow(
      addresses: const ['127.0.0.1'], port: connection.port, token: token);

  /// Posts [bytes] zeros to the token path, in slices so the test never holds
  /// the whole body.
  ///
  /// Any failure is swallowed. A server that stops reading mid-body breaks the
  /// connection under the peer's own writes, so the caller asserts on what the
  /// server kept rather than on what came back.
  Future<void> postBytes(String token, int bytes) async {
    final client = HttpClient();
    try {
      final req = await client
          .postUrl(Uri.parse('http://127.0.0.1:${connection.port}/$token'));
      const slice = 256 * 1024;
      for (var written = 0; written < bytes; written += slice) {
        req.add(Uint8List(min(slice, bytes - written)));
        await req.flush();
      }
      await req.close();
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }

  /// One raw request, returning the status and the body.
  Future<(int, String)> get(String path) async {
    final client = HttpClient();
    try {
      final res = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:${connection.port}$path')))
          .close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    } finally {
      client.close(force: true);
    }
  }

  setUp(() async {
    server = SyncServer();
    // Pinned rather than looked up: what the server reports is the machine's
    // own network, and these tests have to run on one that has none.
    connection = await server.start(utf8.encode(payload),
        addresses: const ['127.0.0.1']);
  });

  tearDown(() async {
    await server.stop();
    server.dispose();
  });

  group('who gets in', () {
    test('a request without the token is refused', () async {
      final (status, body) = await get('/');

      expect(status, HttpStatus.forbidden);
      expect(body, isEmpty);
      expect(server.state.value, SyncServerState.waiting,
          reason: 'a stranger must not even raise a prompt on the sender');
    });

    test('a request with the wrong token is refused', () async {
      final (status, _) = await get('/${connection.token}X');

      expect(status, HttpStatus.forbidden);
      expect(server.state.value, SyncServerState.waiting);
    });

    test('the token alone does not hand over the payload', () async {
      final (status, body) = await get('/${connection.token}');

      expect(status, HttpStatus.accepted);
      expect(body, contains(server.pin));
      expect(body, isNot(contains(payload)));
      expect(server.state.value, SyncServerState.pending);
    });

    test('every session gets its own token and number', () async {
      final other = SyncServer();
      final second = await other.start(utf8.encode(payload),
          addresses: const ['127.0.0.1']);

      expect(second.token, isNot(connection.token));
      expect(second.token.length, 16);
      expect(server.pin, hasLength(4));

      await other.stop();
      other.dispose();
    });
  });

  group('pairing', () {
    test('the payload follows once the sender approves', () async {
      final fetch = SyncClient().fetch(loopback(connection.token));

      // The sender sees the request and lets it through.
      await _until(() => server.state.value == SyncServerState.pending);
      server.approve();

      expect(await fetch, payload);

      await _until(
        () => server.state.value == SyncServerState.served,
      );

      expect(server.state.value, SyncServerState.served);
    });

    test('the receiver is told the number to compare', () async {
      String? seen;
      final fetch = SyncClient()
          .fetch(loopback(connection.token), onPin: (pin) => seen = pin);

      await _until(() => server.state.value == SyncServerState.pending);
      server.approve();
      await fetch;

      expect(seen, isNotNull);
      expect(seen, server.pin,
          reason: 'both screens have to show the same digits');
    });

    test('a payload of a realistic size arrives whole', () async {
      // The transfer only reaches this transport when it is too large for a QR
      // code, so a short test string proves nothing: the failure this guards
      // against is the server closing while the body is still going out, and
      // that only shows up once the body no longer fits in one buffer.
      final big = 'DS2:${'W' * 250000}';
      final other = SyncServer();
      final where = await other.start(utf8.encode(big),
          addresses: const ['127.0.0.1']);

      // The screen stops the server the moment it reports the hand-over, so
      // that has to be the moment the last byte is out.
      final stopped = Completer<void>();
      other.state.addListener(() {
        if (other.state.value == SyncServerState.served && !stopped.isCompleted) {
          stopped.complete(other.stop());
        }
      });

      final fetch = SyncClient().fetch(TransferInvite.forNow(
          addresses: const ['127.0.0.1'],
          port: where.port,
          token: where.token));
      await _until(() => other.state.value == SyncServerState.pending);
      other.approve();

      expect(await fetch, hasLength(big.length));
      await stopped.future;
      other.dispose();
    });

    test('declining turns the receiver away', () async {
      final fetch = SyncClient().fetch(loopback(connection.token));

      await _until(() => server.state.value == SyncServerState.pending);
      server.reject();

      await expectLater(fetch, throwsA(isA<SyncRejectedException>()));
    });
  });

  group('the return leg', () {
    /// Plays the receiver: takes the payload, then answers with [reply].
    Future<void> exchange(String reply) async {
      final client = SyncClient();
      final fetch = client.fetch(loopback(connection.token));
      await _until(() => server.state.value == SyncServerState.pending);
      server.approve();
      await fetch;
      await client.post(loopback(connection.token), reply);
    }

    test('the peer answers with its own side, and that ends the session',
        () async {
      await exchange('DS2:THEIRS');

      await _until(() => server.state.value == SyncServerState.returned);
      expect(server.returnedPayload, 'DS2:THEIRS');
    });

    test('an empty answer ends the wait with nothing to import', () async {
      // What a receiver sends when it does not know the player at all. It has
      // to answer anyway, or the sender sits on its timeout for no reason.
      await exchange('');

      await _until(() => server.state.value == SyncServerState.returned);
      expect(server.returnedPayload, isNull);
    });

    test('nothing is taken before the payload has gone out', () async {
      final client = SyncClient();

      await expectLater(
        client.post(loopback(connection.token), 'DS2:THEIRS'),
        throwsA(isA<Exception>()),
        reason: 'an unapproved peer holding the token must not push data in',
      );
      expect(server.state.value, SyncServerState.waiting);
      expect(server.returnedPayload, isNull);
    });

    test('an answer without the token is refused', () async {
      final client = SyncClient();
      final fetch = client.fetch(loopback(connection.token));
      await _until(() => server.state.value == SyncServerState.pending);
      server.approve();
      await fetch;

      await expectLater(
        client.post(loopback('${connection.token}X'), 'DS2:THEIRS'),
        throwsA(isA<Exception>()),
      );
      expect(server.state.value, SyncServerState.served);
      expect(server.returnedPayload, isNull);
    });

    test('the payload is not handed out again once the exchange is over',
        () async {
      await exchange('DS2:THEIRS');
      await _until(() => server.state.value == SyncServerState.returned);

      final (status, body) = await get('/${connection.token}');

      expect(status, HttpStatus.gone);
      expect(body, isNot(contains(payload)));
    });
  });

  group('size limits', () {
    /// A peer that is not this app: answers 200 on anything, announces
    /// [announced] as the length and then writes [sends] bytes.
    ///
    /// The two are separate on purpose, and that is why the response is
    /// written onto a raw socket rather than through `HttpServer`: a peer is
    /// free to name one length and send another, which is exactly what
    /// `HttpServer` refuses to let a test do.
    Future<(ServerSocket, TransferInvite)> liar(
        {required int announced, required int sends}) async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      listener.listen((socket) async {
        socket.listen((_) {}, onError: (_) {}, cancelOnError: false);
        socket.write('HTTP/1.1 200 OK\r\n');
        if (announced > 0) socket.write('Content-Length: $announced\r\n');
        // Without a length the body runs to the close, which is how a peer
        // asks the receiver to keep reading for as long as it keeps sending.
        socket.write('Connection: close\r\n\r\n');

        try {
          const slice = 64 * 1024;
          for (var written = 0; written < sends; written += slice) {
            socket.add(Uint8List(min(slice, sends - written)));
            await socket.flush();
          }
        } on SocketException {
          // The receiver may intentionally close the connection
          // after detecting that the payload exceeds its size limit.
        } finally {
          socket.destroy();
        }
      });
      return (
        listener,
        TransferInvite.forNow(
            addresses: const ['127.0.0.1'], port: listener.port, token: 'TOKEN')
      );
    }

    test('an announced length above the ceiling is refused before it arrives',
        () async {
      final (peer, conn) = await liar(announced: 4096, sends: 0);
      addTearDown(peer.close);

      await expectLater(
        SyncClient().fetchBytes(conn, maxBytes: 1024),
        throwsA(isA<SyncPayloadTooLargeException>()),
      );
    });

    test('a body that grows past the ceiling is refused as it arrives',
        () async {
      // No announced length at all, which is what a peer sends when it wants
      // the receiver to keep reading. Only weighing the chunks catches it.
      final (peer, conn) = await liar(announced: 0, sends: 512 * 1024);
      addTearDown(peer.close);

      await expectLater(
        SyncClient().fetchBytes(conn, maxBytes: 1024),
        throwsA(isA<SyncPayloadTooLargeException>()),
      );
    });

    test('a body inside the ceiling still arrives whole', () async {
      final (peer, conn) = await liar(announced: 1024, sends: 1024);
      addTearDown(peer.close);

      expect(await SyncClient().fetchBytes(conn, maxBytes: 1024),
          hasLength(1024));
    });

    test('an oversized answer on the return leg is refused', () async {
      final client = SyncClient();
      final fetch = client.fetch(loopback(connection.token));
      await _until(() => server.state.value == SyncServerState.pending);
      server.approve();
      await fetch;

      await postBytes(connection.token, kMaxSyncTransferBytes + 1024 * 1024);

      // What the peer sees is deliberately not pinned. The server stops
      // reading mid-body, so whether the 413 gets back or the socket breaks
      // under the peer's own writes is up to the timing. What has to hold is
      // that nothing was kept: this device's own side is already out, and only
      // the direction back is lost, which is the same outcome as a peer that
      // never answered and which the return timer already covers.
      expect(server.state.value, SyncServerState.served);
      expect(server.returnedPayload, isNull);
    });
  });

  group('handing a database over', () {
    /// One raw request that is read to the end, which is what moves the server
    /// from waiting to pending. The peer polls, so the payload only goes out on
    /// a second request after the user has approved.
    Future<void> ask(TransferInvite where) async {
      final socket = await Socket.connect('127.0.0.1', where.port);
      socket.write('GET /${where.token} HTTP/1.1\r\nHost: t\r\n\r\n');
      await socket.flush();
      await socket.first;
      socket.destroy();
    }

    /// A one-way server holding [bytes] of payload, already approved.
    Future<(SyncServer, TransferInvite)> approvedServer([int bytes = 64 * 1024]) async {
      final other = SyncServer();
      final where = await other.start(List.filled(bytes, 7),
          twoWay: false,
          contentType: ContentType.binary,
          addresses: const ['127.0.0.1']);

      await ask(where);
      await _until(() => other.state.value == SyncServerState.pending);
      other.approve();
      return (other, where);
    }

    test('the sender is not done until the peer says it has the file',
        () async {
      // The failure this pins. Writing the last byte is not delivering it:
      // `close` hands the payload to the kernel and the peer may still have
      // most of a database to pull out of the buffers. The sending screen took
      // the hand-over as the end, stopped the server and, on a transfer over a
      // network it had raised, took the network down with it. The receiver sat
      // at part of the file with nothing to show for it, because a network that
      // disappears breaks no connection, it just goes quiet.
      final previous = SyncServer.confirmationTimeout;
      SyncServer.confirmationTimeout = const Duration(milliseconds: 400);
      addTearDown(() => SyncServer.confirmationTimeout = previous);

      final (other, where) = await approvedServer();
      addTearDown(other.dispose);

      // A peer that reads every byte and never says so.
      final socket = await Socket.connect('127.0.0.1', where.port);
      addTearDown(socket.destroy);
      socket.write('GET /${where.token} HTTP/1.1\r\nHost: t\r\n\r\n');
      await socket.flush();
      var received = 0;
      socket.listen((chunk) => received += chunk.length,
          onError: (_) {}, cancelOnError: false);

      await _until(() => received >= 64 * 1024);
      expect(other.state.value, SyncServerState.approved,
          reason: 'every byte is written, and the sender still waits');

      // Only the peer vanishing ends it without a word, and then finishing is
      // the right answer: the payload is out and nothing is left to wait for.
      await _until(() => other.state.value == SyncServerState.served);
    });

    test('the client says so, and the sender stops right after', () async {
      // The confirmation timeout stays at its full length here on purpose: a
      // hand-over that ends quickly proves the peer spoke, not that the wait
      // ran out.
      final (other, where) = await approvedServer();
      addTearDown(other.dispose);

      final started = DateTime.now();
      final bytes = await SyncClient().fetchBytes(where);

      expect(bytes, hasLength(64 * 1024));
      await _until(() => other.state.value == SyncServerState.served);
      expect(DateTime.now().difference(started),
          lessThan(const Duration(seconds: 5)));
    });

    test('a peer that never reads does not hold the sender forever', () async {
      // A peer that stopped reading in the middle blocks the write, and the
      // screen has to be able to leave: this is the app going to the background
      // halfway through a database.
      final previousGrace = SyncServer.drainGrace;
      SyncServer.drainGrace = const Duration(milliseconds: 200);
      addTearDown(() => SyncServer.drainGrace = previousGrace);

      // Past any socket buffer, so the write cannot finish while nobody reads.
      final (other, where) = await approvedServer(24 * 1024 * 1024);
      addTearDown(other.dispose);

      final socket = await Socket.connect('127.0.0.1', where.port);
      addTearDown(socket.destroy);
      socket.write('GET /${where.token} HTTP/1.1\r\nHost: t\r\n\r\n');
      await socket.flush();
      socket.listen((_) {}, onError: (_) {}, cancelOnError: false).pause();

      await _until(() => other.progress.value > 0);
      await other.stop().timeout(const Duration(seconds: 5));
      expect(other.isRunning, isFalse);
    });
  });

  group('the invitation', () {
    test('names the addresses the server was told to report', () {
      expect(connection.addresses, ['127.0.0.1']);
      expect(connection.port, isPositive);
      expect(connection.token, hasLength(16));
    });

    test('stays inside the dense QR character set', () {
      // Lower case or braces would push the code into the byte mode, which is
      // a third less dense for no reason.
      final payload = connection.qrPayload(kSyncWifiPrefix);
      expect(RegExp(r'^[0-9A-Z $%*+\-./:]+$').hasMatch(payload), isTrue,
          reason: payload);
    });
  });

  group('what will not start', () {
    test('a device on no network is told so, and binds nothing', () async {
      final other = SyncServer();
      addTearDown(other.dispose);

      await expectLater(
        other.start(utf8.encode(payload), addresses: const []),
        throwsA(isA<TransferStartException>().having(
            (e) => e.reason, 'reason', TransferStartFailure.noLocalAddress)),
      );
      expect(other.isRunning, isFalse,
          reason: 'a socket nobody can reach is one nobody has to stop');
    });
  });

  group('several addresses', () {
    test('the one that answers is found past the ones that do not', () async {
      // What a phone offers when it is on Wi-Fi and has a hotspot up: only one
      // of the addresses is on the network the peer joined.
      final fetch = SyncClient().fetch(TransferInvite.forNow(
        // One address that goes nowhere is enough to prove the point, and
        // each one costs the probe timeout before the next is tried.
        addresses: ['10.255.255.1', '127.0.0.1'],
        port: connection.port,
        token: connection.token,
      ));

      await _until(() => server.state.value == SyncServerState.pending);
      server.approve();

      expect(await fetch, payload);
    });

    test('a peer that answers on none of them is named unreachable', () async {
      // Not a timeout: a timeout means the other device heard this one and the
      // user has not confirmed. Nothing here was ever heard.
      await expectLater(
        SyncClient().fetch(TransferInvite.forNow(
            addresses: const ['10.255.255.1'], port: 1, token: 'TOKEN')),
        throwsA(isA<TransferUnreachableException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a code that has expired is refused before anything is asked',
        () async {
      await expectLater(
        SyncClient().fetch(TransferInvite(
            addresses: const ['127.0.0.1'],
            port: connection.port,
            token: connection.token,
            expiresAt:
                DateTime.now().subtract(const Duration(seconds: 1)))),
        throwsA(isA<TransferInviteExpiredException>()),
      );
    });
  });
}

/// Waits until [condition] holds, so a test can react to the server rather
/// than sleep for a fixed time and hope.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('the server never reached the expected state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
