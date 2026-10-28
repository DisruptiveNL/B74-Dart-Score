import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartscore_app/services/sync_codec.dart';
import 'package:dartscore_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sync payload is the one place where a throw is not stored but described,
/// so a field the encoder forgets is gone for good on the receiving device.
/// These tests pin the round trip field by field, and pin the size too: how many
/// throws fit into one QR code is what decides whether a sync needs the camera
/// for a moment or a shared Wi-Fi.
void main() {
  /// A throw with sensible defaults, so each test only states what it is about.
  SyncThrow t({
    int score = 60,
    int dartsUsed = 3,
    required int remainingBefore,
    required int thrownAt,
    bool bust = false,
    int leg = 1,
    int set = 1,
    int checkoutDarts = 0,
  }) => SyncThrow(
    score: score,
    dartsUsed: dartsUsed,
    remainingBefore: remainingBefore,
    thrownAt: thrownAt,
    bust: bust,
    leg: leg,
    set: set,
    checkoutDarts: checkoutDarts,
  );

  /// A packet around [throws], with every non-throw field filled in.
  SyncPacket packetOf(List<SyncThrow> throws, {int? rangeDays}) => SyncPacket(
    version: 2,
    senderDevice: 'iPhone',
    playerUuid: '3f2a1c9e-7b4d-4e51-9a08-6c2d5f7b1e33',
    playerName: 'Björn',
    favoriteDoubles: 'D20,D16',
    localStatsJson: '{"total_darts":1200,"count_180":7}',
    rangeDays: rangeDays,
    stats: const SyncStats(
      totalDarts: 1200,
      totalVisits: 400,
      average: 62.37,
      legsWon: 18,
      highestVisit: 180,
      busts: 21,
      count180: 7,
    ),
    throws: throws,
  );

  /// Asserts that [packet] survives encoding and decoding unchanged.
  void expectRoundTrip(SyncPacket packet) {
    final decoded = decodeSyncPayload(encodeSyncPayload(packet));

    expect(decoded.senderDevice, packet.senderDevice);
    expect(decoded.playerUuid, packet.playerUuid);
    expect(decoded.playerName, packet.playerName);
    expect(decoded.favoriteDoubles, packet.favoriteDoubles);
    expect(decoded.localStatsJson, packet.localStatsJson);
    expect(decoded.rangeDays, packet.rangeDays);
    expect(decoded.senderDeviceId, packet.senderDeviceId);

    expect(
      decoded.origins.map((o) => o.device),
      packet.origins.map((o) => o.device),
    );
    expect(
      decoded.origins.map((o) => o.snapshotJson),
      packet.origins.map((o) => o.snapshotJson),
    );

    expect(decoded.stats.totalDarts, packet.stats.totalDarts);
    expect(decoded.stats.totalVisits, packet.stats.totalVisits);
    expect(decoded.stats.average, closeTo(packet.stats.average, 0.005));
    expect(decoded.stats.legsWon, packet.stats.legsWon);
    expect(decoded.stats.highestVisit, packet.stats.highestVisit);
    expect(decoded.stats.busts, packet.stats.busts);
    expect(decoded.stats.count180, packet.stats.count180);

    expect(decoded.throws.length, packet.throws.length);
    for (var i = 0; i < packet.throws.length; i++) {
      final a = packet.throws[i];
      final b = decoded.throws[i];
      final at = 'throw $i';
      expect(b.score, a.score, reason: at);
      expect(b.dartsUsed, a.dartsUsed, reason: at);
      expect(b.remainingBefore, a.remainingBefore, reason: at);
      expect(b.thrownAt, a.thrownAt, reason: at);
      expect(b.bust, a.bust, reason: at);
      expect(b.leg, a.leg, reason: at);
      expect(b.set, a.set, reason: at);
      expect(b.checkoutDarts, a.checkoutDarts, reason: at);
    }
  }

  group('base45', () {
    test('round trips bytes of both even and odd length', () {
      for (final length in [0, 1, 2, 3, 4, 5, 255, 256, 1000, 1001]) {
        final bytes = List.generate(length, (i) => (i * 37 + 11) % 256);
        expect(
          base45Decode(base45Encode(bytes)),
          bytes,
          reason: 'length $length',
        );
      }
    });

    test('covers the whole byte range', () {
      final bytes = List.generate(256, (i) => i);
      expect(base45Decode(base45Encode(bytes)), bytes);
    });

    test('matches the examples in RFC 9285', () {
      expect(base45Encode(utf8.encode('AB')), 'BB8');
      expect(base45Encode(utf8.encode('Hello!!')), '%69 VD92EX0');
      expect(base45Encode(utf8.encode('base-45')), 'UJCLQE7W581');
      expect(utf8.decode(base45Decode('QED8WEX0')), 'ietf!');
    });

    test('produces only characters a QR code can carry densely', () {
      final bytes = List.generate(2000, (i) => (i * 91 + 7) % 256);
      expect(isAlphanumericSafe(base45Encode(bytes)), isTrue);
    });

    test('rejects a corrupted payload', () {
      expect(
        () => base45Decode('AB_'),
        throwsFormatException,
        reason: 'underscore is not in the alphabet',
      );
      expect(
        () => base45Decode('A'),
        throwsFormatException,
        reason: 'a single character cannot be a group',
      );
      expect(
        () => base45Decode(':::'),
        throwsFormatException,
        reason: 'group value above 0xFFFF',
      );
    });
  });

  group('packet round trip', () {
    test('carries a leg with a bust and a checkout', () {
      const start = 1770000000000;
      expectRoundTrip(
        packetOf([
          t(score: 180, remainingBefore: 501, thrownAt: start),
          t(score: 180, remainingBefore: 321, thrownAt: start + 41000),
          // Busts leave the remaining score untouched, which the decoder has to
          // reproduce rather than subtract.
          t(
            score: 60,
            remainingBefore: 141,
            thrownAt: start + 77000,
            bust: true,
          ),
          t(score: 60, remainingBefore: 141, thrownAt: start + 118000),
          // The checkout, and the only visit of the leg that ever put a dart on
          // a finish. 81 goes T19, D12, so one of its three darts flew at the
          // double.
          t(
            score: 81,
            dartsUsed: 3,
            remainingBefore: 81,
            thrownAt: start + 155000,
            checkoutDarts: 1,
          ),
        ]),
      );
    });

    test('carries every dart count a visit can put on a finish', () {
      const start = 1770000000000;
      expectRoundTrip(
        packetOf([
          for (var darts = 0; darts <= 3; darts++)
            t(
              score: 0,
              remainingBefore: 40,
              thrownAt: start + darts * 40000,
              checkoutDarts: darts,
            ),
        ]),
      );
    });

    test('carries leg and set changes', () {
      const start = 1770000000000;
      expectRoundTrip(
        packetOf([
          t(score: 100, remainingBefore: 501, thrownAt: start, leg: 1, set: 1),
          t(
            score: 140,
            remainingBefore: 501,
            thrownAt: start + 60000,
            leg: 2,
            set: 1,
          ),
          t(
            score: 45,
            remainingBefore: 501,
            thrownAt: start + 130000,
            leg: 1,
            set: 2,
          ),
        ]),
      );
    });

    test('carries one and two dart visits', () {
      const start = 1770000000000;
      expectRoundTrip(
        packetOf([
          t(score: 40, dartsUsed: 1, remainingBefore: 40, thrownAt: start),
          t(
            score: 32,
            dartsUsed: 2,
            remainingBefore: 32,
            thrownAt: start + 55000,
          ),
          t(
            score: 0,
            dartsUsed: 3,
            remainingBefore: 170,
            thrownAt: start + 96000,
          ),
        ]),
      );
    });

    test('carries a packet without throws', () {
      expectRoundTrip(packetOf([]));
    });

    test('carries a range and a missing snapshot', () {
      final packet = SyncPacket(
        version: 2,
        senderDevice: 'Android',
        playerUuid: 'a1',
        playerName: 'A',
        favoriteDoubles: '',
        rangeDays: 7,
        stats: const SyncStats(
          totalDarts: 0,
          totalVisits: 0,
          average: 0,
          legsWon: 0,
          highestVisit: 0,
          busts: 0,
          count180: 0,
        ),
        throws: [t(remainingBefore: 501, thrownAt: 1770000000000)],
      );
      expectRoundTrip(packet);
      expect(
        decodeSyncPayload(encodeSyncPayload(packet)).localStatsJson,
        isNull,
      );
    });

    test('keeps timestamps to the millisecond, they are the dedup key', () {
      const start = 1770000000123;
      final packet = packetOf([
        t(remainingBefore: 501, thrownAt: start),
        t(remainingBefore: 441, thrownAt: start + 40317),
        t(remainingBefore: 381, thrownAt: start + 91004),
      ]);
      final decoded = decodeSyncPayload(encodeSyncPayload(packet));
      expect(decoded.throws.map((x) => x.thrownAt), [
        start,
        start + 40317,
        start + 91004,
      ]);
    });
  });

  group('origins', () {
    const start = 1770000000000;

    /// A packet of [throws], each attributed to the matching entry of
    /// [throwOrigins], sent by device A which also passes on device C.
    SyncPacket attributed(List<SyncThrow> throws, List<String> throwOrigins) =>
        SyncPacket(
          version: 2,
          senderDevice: 'iPhone',
          senderDeviceId: 'DEVICEAAAAAAAAAA',
          playerUuid: 'a1',
          playerName: 'A',
          favoriteDoubles: '',
          origins: const [
            SyncOrigin(
              device: 'DEVICEAAAAAAAAAA',
              snapshotJson: '{"total_darts":9}',
            ),
            SyncOrigin(
              device: 'DEVICECCCCCCCCCC',
              snapshotJson: '{"total_darts":3}',
            ),
          ],
          throwOrigins: throwOrigins,
          stats: const SyncStats(
            totalDarts: 0,
            totalVisits: 0,
            average: 0,
            legsWon: 0,
            highestVisit: 0,
            busts: 0,
            count180: 0,
          ),
          throws: throws,
        );

    test('carry one snapshot per device through a round trip', () {
      expectRoundTrip(
        attributed(
          [t(remainingBefore: 501, thrownAt: start)],
          const ['DEVICEAAAAAAAAAA'],
        ),
      );
    });

    test('say which device each throw came from', () {
      final packet = attributed(
        [
          t(remainingBefore: 501, thrownAt: start),
          t(remainingBefore: 441, thrownAt: start + 40000),
          t(remainingBefore: 381, thrownAt: start + 80000),
        ],
        const ['DEVICEAAAAAAAAAA', 'DEVICECCCCCCCCCC', 'DEVICECCCCCCCCCC'],
      );

      final decoded = decodeSyncPayload(encodeSyncPayload(packet));

      expect([
        for (var i = 0; i < 3; i++) decoded.originOfThrow(i),
      ], packet.throwOrigins);
    });

    test('cost nothing per throw when they are all the sender own', () {
      final throws = [
        for (var i = 0; i < 200; i++)
          t(remainingBefore: 501 - i, thrownAt: start + i * 40000),
      ];
      final own = List.filled(200, 'DEVICEAAAAAAAAAA');

      final attributedSize = encodeSyncBytes(attributed(throws, own)).length;
      final plainSize = encodeSyncBytes(attributed(throws, const [])).length;

      expect(
        attributedSize,
        plainSize,
        reason: 'the sender is who a throw belongs to unless stated',
      );

      // And it still reads back as the sender's own.
      final decoded = decodeSyncPayload(
        encodeSyncPayload(attributed(throws, own)),
      );
      expect(decoded.originOfThrow(0), 'DEVICEAAAAAAAAAA');
    });

    test('leave a packet from before them readable', () {
      // No sender id and no origins is what an older app sends, and it has to
      // stay importable rather than be refused as a format nobody knows.
      final packet = packetOf([t(remainingBefore: 501, thrownAt: start)]);

      final decoded = decodeSyncPayload(encodeSyncPayload(packet));

      expect(decoded.senderDeviceId, isEmpty);
      expect(decoded.origins, isEmpty);
      expect(
        decoded.localStatsJson,
        packet.localStatsJson,
        reason: 'the one snapshot such a packet has still arrives',
      );
      expect(decoded.originOfThrow(0), isEmpty);
    });

    test('are rejected when a throw names one that is not there', () {
      final packet = attributed(
        [t(remainingBefore: 501, thrownAt: start)],
        const ['DEVICECCCCCCCCCC'],
      );
      final bytes = encodeSyncBytes(packet);

      // The last byte is the single origin index. Pointing it past the end of
      // the table is what a corrupted payload looks like.
      final raw = Uint8List.fromList(gzip.decode(bytes));
      raw[raw.length - 1] = 9;
      final corrupted = Uint8List.fromList(gzip.encode(raw));

      expect(() => decodeSyncBytes(corrupted), throwsFormatException);
    });
  });

  group('payload size', () {
    /// 500 visits shaped like real play: a 501 leg finished in 15 to 18 visits,
    /// the usual spread of scores, an occasional bust, roughly 40 seconds
    /// between one visit and the player's next.
    List<SyncThrow> realisticThrows(int count) {
      final random = Random(42);
      const scores = [
        26,
        41,
        45,
        55,
        60,
        60,
        66,
        81,
        85,
        95,
        100,
        121,
        140,
        180,
      ];

      final throws = <SyncThrow>[];
      var time = 1770000000000;
      var leg = 1;
      var remaining = 501;

      while (throws.length < count) {
        final bust = random.nextInt(12) == 0;
        var score = scores[random.nextInt(scores.length)];
        if (score > remaining) score = bust ? score : remaining;

        throws.add(
          SyncThrow(
            score: score,
            dartsUsed: 3,
            remainingBefore: remaining,
            thrownAt: time,
            bust: bust,
            leg: leg,
            set: 1,
          ),
        );

        time += 35000 + random.nextInt(15000);
        if (!bust) remaining -= score;
        if (remaining <= 1) {
          leg++;
          remaining = 501;
        }
      }
      return throws;
    }

    /// A lifetime snapshot of the shape `local_stats_json` really has: about
    /// two dozen counters plus the twenty most recent throws. It rides along in
    /// every sync, so it eats into what is left for the throws themselves.
    String realisticSnapshot() {
      final buffer = StringBuffer('{');
      for (var i = 0; i < 25; i++) {
        buffer.write('"counter_number_$i":${1000 + i},');
      }
      buffer.write('"recent_throws":[');
      for (var i = 0; i < 20; i++) {
        buffer.write(
          '{"score":${60 + i},"darts_used":3,"bust":0,'
          '"remaining_before":${501 - i * 20},'
          '"thrown_at":${1770000000000 + i * 41000}}',
        );
        if (i < 19) buffer.write(',');
      }
      buffer.write(']}');
      return buffer.toString();
    }

    test('a long evening of play fits into a single QR code', () {
      final transmission = prepareTransmission(
        SyncPacket(
          version: 2,
          senderDevice: 'iPhone',
          playerUuid: '3f2a1c9e-7b4d-4e51-9a08-6c2d5f7b1e33',
          playerName: 'Björn',
          favoriteDoubles: 'D20,D16',
          localStatsJson: realisticSnapshot(),
          stats: const SyncStats(
            totalDarts: 1200,
            totalVisits: 400,
            average: 62.37,
            legsWon: 18,
            highestVisit: 180,
            busts: 21,
            count180: 7,
          ),
          throws: realisticThrows(330),
        ),
      );

      expect(
        transmission.transport,
        SyncTransport.staticQr,
        reason:
            'encoded length was ${transmission.payload.length}, '
            'the static limit is $kStaticQrMaxChars',
      );
    });

    /// Guards the cost per throw against a change that quietly makes the format
    /// wordy again. About four of these bytes are the throw's timestamp, which
    /// is close to real randomness and does not compress; the rest is the score,
    /// the flags and the occasional leg change. Base45 costs 1.5 characters per
    /// byte against base64's 1.33, and buys back far more than that in what a
    /// code of the same size can hold.
    test('costs no more than seven characters per throw', () {
      final base = encodeSyncPayload(packetOf([])).length;
      final full = encodeSyncPayload(packetOf(realisticThrows(500))).length;

      final perThrow = (full - base) / 500;
      expect(perThrow, lessThan(7.0), reason: '$perThrow chars per throw');
    });

    test('is less than half the size of the JSON format it replaces', () {
      final throws = realisticThrows(500);
      final binary = encodeSyncPayload(packetOf(throws)).length;
      final json =
          'QR1:${base64Url.encode(gzip.encode(utf8.encode(jsonEncode(packetOf(throws).toJson()))))}'
              .length;

      expect(
        binary * 2,
        lessThan(json),
        reason: 'binary $binary chars vs json $json chars',
      );
    });
  });

  group('animated transfer', () {
    /// Enough throws to need several blocks.
    SyncPacket bigPacket([int throws = 900]) => packetOf(
      List.generate(
        throws,
        (i) => t(
          score: 60 - (i % 7),
          remainingBefore: 501 - (i % 8) * 60,
          thrownAt: 1770000000000 + i * 41000,
          leg: 1 + i ~/ 16,
        ),
      ),
    );

    /// Feeds frames to a decoder, dropping a share of them, and returns how
    /// many had to pass by before the payload was complete.
    ///
    /// [lossRate] is the share the camera misses. [burst] drops that many
    /// frames in a row when it misses, which is what a hand tremor or a
    /// refocus does, and what a numbered sequence handles worst.
    int framesUntilComplete(
      Uint8List data, {
      double lossRate = 0,
      int burst = 1,
      int seed = 1,
      int startOffset = 0,
      int limit = 20000,
    }) {
      final encoder = SyncFountainEncoder(data, startOffset: startOffset);
      final decoder = SyncFountainDecoder();
      final random = Random(seed);

      var skipping = 0;
      for (var i = 0; i < limit; i++) {
        if (skipping > 0) {
          skipping--;
        } else if (random.nextDouble() < lossRate) {
          skipping = burst - 1;
        } else {
          decoder.add(encoder.frameAt(i));
          if (decoder.isComplete) {
            expect(decoder.assemble(), data);
            return i + 1;
          }
        }
      }
      fail('did not decode within $limit frames');
    }

    /// Mean frames needed over [trials] transfers, each starting at a different
    /// point in the seed space the way a real one does.
    double meanFrames(
      Uint8List data, {
      double lossRate = 0,
      int burst = 1,
      int trials = 25,
    }) {
      var total = 0;
      for (var trial = 0; trial < trials; trial++) {
        total += framesUntilComplete(
          data,
          lossRate: lossRate,
          burst: burst,
          seed: trial + 1,
          startOffset: trial * 7919,
        );
      }
      return total / trials;
    }

    test('needs only a little more than the block count', () {
      final data = encodeSyncBytes(bigPacket());
      final blocks = SyncFountainEncoder(data).sourceBlocks;
      expect(blocks, greaterThan(1));

      // Measured at about 1.25 for these sizes. Well over half again would
      // mean the degree distribution or the seed scrambling has broken.
      final mean = meanFrames(data);
      expect(
        mean,
        lessThan(blocks * 1.5),
        reason: '$mean frames for $blocks blocks',
      );
    });

    test('does not wait for any particular frame', () {
      // The point of the whole exercise: a numbered sequence missing frame 137
      // has to wait a full loop for it, a fountain code just takes the next
      // frame instead. Dropping a fifth of them must cost about that fifth in
      // frames passing by, and nothing beyond it.
      final data = encodeSyncBytes(bigPacket());

      final clean = meanFrames(data);
      final lossy = meanFrames(data, lossRate: 0.2);

      expect(
        lossy * 0.8,
        lessThan(clean * 1.2),
        reason: 'clean $clean, lossy $lossy',
      );
    });

    test('survives frames going missing in bursts', () {
      // A hand tremor or a refocus takes out a run of frames at once, which is
      // what a numbered sequence handles worst.
      final data = encodeSyncBytes(bigPacket());

      final scattered = meanFrames(data, lossRate: 0.1);
      final bursty = meanFrames(data, lossRate: 0.0125, burst: 8);

      expect(
        bursty,
        lessThan(scattered * 1.3),
        reason: 'scattered $scattered, bursty $bursty',
      );
    });

    test('decodes across a spread of payload sizes', () {
      for (final throws in [1, 40, 400, 2000]) {
        final data = encodeSyncBytes(bigPacket(throws));
        expect(
          () => framesUntilComplete(data, lossRate: 0.15),
          returnsNormally,
          reason: '$throws throws',
        );
      }
    });

    test('every frame fits the size a QR code can show', () {
      final encoder = SyncFountainEncoder(encodeSyncBytes(bigPacket()));
      for (var i = 0; i < 50; i++) {
        final frame = encoder.frameAt(i);
        expect(
          frame.length,
          lessThanOrEqualTo(kFrameMaxChars),
          reason: 'a version 15 code at level M holds 600 of these',
        );
        expect(
          isAlphanumericSafe(frame),
          isTrue,
          reason:
              'a frame outside the alphanumeric set loses a third of '
              'its capacity to the byte mode',
        );
      }
    });

    test('reports progress while blocks are still missing', () {
      final encoder = SyncFountainEncoder(encodeSyncBytes(bigPacket()));
      final decoder = SyncFountainDecoder();

      decoder.add(encoder.frameAt(0));
      expect(decoder.sourceBlocks, encoder.sourceBlocks);
      expect(decoder.isComplete, isFalse);
      expect(decoder.assemble, throwsFormatException);
    });

    test('starts over when frames come from a different transfer', () {
      final first = SyncFountainEncoder(encodeSyncBytes(bigPacket()));
      final second = SyncFountainEncoder(
        encodeSyncBytes(packetOf([t(remainingBefore: 501, thrownAt: 1)])),
      );

      final decoder = SyncFountainDecoder();
      decoder.add(first.frameAt(0));
      decoder.add(first.frameAt(1));

      for (var i = 0; i < 20 && !decoder.isComplete; i++) {
        decoder.add(second.frameAt(i));
      }

      expect(decoder.isComplete, isTrue);
      expect(decoder.sourceBlocks, second.sourceBlocks);
      expect(decodeSyncBytes(decoder.assemble()).throws.single.thrownAt, 1);
    });

    test('ignores anything that is not a frame', () {
      final decoder = SyncFountainDecoder();
      expect(decoder.add('https://example.com'), isFalse);
      expect(decoder.add('DS3:oops'), isFalse);
      expect(
        decoder.add('DS3:1:0:5:ABC:QQ'),
        isFalse,
        reason: 'a transfer of no blocks',
      );
      expect(decoder.sourceBlocks, 0);
    });

    test('refuses a frame claiming more length than its blocks hold', () {
      // The header decides where [assemble] cuts the payload, so a length past
      // the blocks would leave the cut out of range rather than merely wrong.
      final encoder = SyncFountainEncoder(
        Uint8List.fromList(List.generate(300, (i) => i % 256)),
        startOffset: 0,
      );
      final parts = encoder
          .frameAt(0)
          .substring(kSyncFramePrefix.length)
          .split(':');
      final overlong =
          '$kSyncFramePrefix${parts[0]}:${parts[1]}:'
          'zzzz:${parts[3]}:${parts.sublist(4).join(':')}';

      final decoder = SyncFountainDecoder();
      expect(decoder.add(overlong), isFalse);
      expect(decoder.isComplete, isFalse);
      expect(decoder.sourceBlocks, 0);
    });

    test('a payload that arrives corrupt is refused, not handed on', () {
      // The checksum covers the data, not the header, so a frame whose blocks
      // do not add up to it completes the transfer and fails here. The scan
      // screen has to see this as a read failure it can report.
      final data = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final encoder = SyncFountainEncoder(data, startOffset: 0);
      final parts = encoder
          .frameAt(0)
          .substring(kSyncFramePrefix.length)
          .split(':');
      final wrongSum =
          '$kSyncFramePrefix${parts[0]}:${parts[1]}:'
          '${parts[2]}:abcd:${parts.sublist(4).join(':')}';

      final decoder = SyncFountainDecoder();
      decoder.add(wrongSum);
      expect(
        decoder.isComplete,
        isTrue,
        reason: 'the blocks are all there, only they do not add up',
      );
      expect(decoder.assemble, throwsFormatException);
    });

    test('the two sides agree on which blocks a frame combines', () {
      // Sender and receiver each derive this from the seed alone, so a drift
      // between the two generators would decode to plausible looking rubbish
      // rather than to an error.
      final data = encodeSyncBytes(bigPacket());
      final sent = framesUntilComplete(data, lossRate: 0.3, seed: 99);
      expect(sent, greaterThan(0));
    });
  });

  group('animation timing', () {
    test('the camera samples faster than the sender changes frames', () {
      // If these two are equal, both sides run at the same rate with no fixed
      // phase between them, and a good share of the frames is never sampled.
      // A transfer then needs several passes for no visible reason.
      expect(kScannerDetectionTimeout, lessThan(kChunkFrameDuration));
    });

    test('a frame outlasts several display refreshes', () {
      // Below about three refreshes at 60Hz the camera starts catching frames
      // mid change, which decodes to nothing.
      const refreshesAt60Hz = 1000 / 60;
      expect(
        kChunkFrameDuration.inMilliseconds / refreshesAt60Hz,
        greaterThanOrEqualTo(3),
      );
    });
  });

  group('transport choice', () {
    /// A packet with roughly [visits] visits, to grow a payload on demand.
    SyncPacket sized(int visits) => packetOf(
      List.generate(
        visits,
        (i) => t(
          score: 60 - (i % 7),
          remainingBefore: 501 - (i % 8) * 60,
          thrownAt: 1770000000000 + i * 41000,
          leg: 1 + i ~/ 16,
        ),
      ),
    );

    test('grows from one code to a stream to the server', () {
      expect(prepareTransmission(sized(50)).transport, SyncTransport.staticQr);
      expect(
        prepareTransmission(sized(3000)).transport,
        SyncTransport.animatedQr,
      );
      expect(prepareTransmission(sized(60000)).transport, SyncTransport.server);
    });

    test('an animated transfer stays inside the block cap', () {
      final animated = prepareTransmission(sized(3000));
      expect(animated.sourceBlocks, lessThanOrEqualTo(kMaxSourceBlocks));
      expect(animated.estimatedDuration.inSeconds, greaterThan(0));
    });
  });

  group('size limits', () {
    /// Gzips [bytes] worth of zeros without ever holding them, which is what
    /// makes a bomb cheap to build and expensive to open.
    Uint8List bomb(int bytes) {
      final out = BytesBuilder(copy: false);
      final sink = gzip.encoder.startChunkedConversion(
        ByteConversionSink.withCallback(out.add),
      );
      final chunk = Uint8List(1024 * 1024);
      for (var written = 0; written < bytes; written += chunk.length) {
        sink.add(chunk);
      }
      sink.close();
      return out.takeBytes();
    }

    test('a packet that expands past the ceiling is refused', () {
      final packed = bomb(kMaxInflatedSyncBytes + 1024 * 1024);

      // The point of the ceiling: a few dozen kilobytes on the wire asking for
      // as much memory as the sender cares to name.
      expect(packed.length, lessThan(1024 * 1024));
      expect(
        () => decodeSyncBytes(packed),
        throwsA(isA<SyncPayloadTooLargeException>()),
      );
    });

    test('a real packet still decodes', () {
      // The ceiling has to sit far enough above the honest case that no user
      // ever meets it, so the round trip is what proves it is not in the way.
      final packet = packetOf([
        for (var i = 0; i < 500; i++)
          t(remainingBefore: 501 - i, thrownAt: 1700000000000 + i),
      ]);

      expect(decodeSyncBytes(encodeSyncBytes(packet)).throws, hasLength(500));
    });
  });

  group('older senders', () {
    test('a v1 JSON payload still imports', () {
      final packet = packetOf([
        t(score: 180, remainingBefore: 501, thrownAt: 1770000000000),
        t(score: 60, remainingBefore: 321, thrownAt: 1770000041000, bust: true),
      ]);

      final legacy =
          'QR1:${base64Url.encode(gzip.encode(utf8.encode(jsonEncode(packet.toJson()))))}';

      final decoded = decodeSyncPayload(legacy);
      expect(decoded.playerName, packet.playerName);
      expect(decoded.throws.length, 2);
      expect(decoded.throws.last.bust, isTrue);
      expect(decoded.throws.last.thrownAt, 1770000041000);
    });

    test('an unknown payload is rejected', () {
      expect(() => decodeSyncPayload('hello'), throwsFormatException);
    });
  });
}
