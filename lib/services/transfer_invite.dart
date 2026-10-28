import 'dart:convert';

import 'sync_codec.dart';

// ── Prefixes ──────────────────────────────────────────────────────────────────

/// Marks the QR code that carries a Wi-Fi profile sync's connection details.
const String kSyncWifiPrefix = 'DSW:';

/// Marks the QR code that carries a whole-database transfer's connection
/// details.
///
/// Its own prefix so the two cannot be mixed up: a database replaces the
/// receiving device, a profile is merged into it, and scanning one code in the
/// screen meant for the other has to fail rather than half work.
const String kBackupWifiPrefix = 'DSB:';

// ── Lifetime ──────────────────────────────────────────────────────────────────

/// How long a connection code stays good for.
///
/// Long enough that a user can walk over to the other device, short enough that
/// a screenshot of the code is worthless by the time anyone finds it. The
/// server is usually gone well before this, but a code outliving its screen is
/// the case worth naming: the peer then fails on an expired invitation instead
/// of on a timeout that says nothing.
const Duration kInviteLifetime = Duration(minutes: 5);

/// Most addresses an invitation is believed when it names them.
///
/// [TransferInvite] never builds more than [kMaxTransferAddresses], and this is
/// the ceiling on the way back in: a peer is free to write whatever it likes
/// into a QR code, and every address it names costs the receiver a round of
/// probing.
const int _kMaxParsedAddresses = 8;

// ── Hotspot credentials ───────────────────────────────────────────────────────

/// The Wi-Fi network a device raised for one transfer.
///
/// Travels inside the connection code so a single scan both joins the network
/// and reaches the server on it. Only ever filled by the device hosting the
/// hotspot; an ordinary transfer over a shared Wi-Fi leaves it null.
class HotspotCredentials {
  final String ssid;
  final String passphrase;

  const HotspotCredentials({required this.ssid, required this.passphrase});
}

// ── Invitation ────────────────────────────────────────────────────────────────

/// Everything a peer needs to reach a running `SyncServer`, as it travels in a
/// QR code.
///
/// Carried as a base45 encoded JSON record rather than as delimited text. The
/// format this replaced was three colon-separated fields, which left room for
/// exactly one address and could not grow: adding a field broke the parser, and
/// an SSID with a colon or a lowercase letter broke both the split and the QR
/// code's alphanumeric mode. Base45 is the alphabet the sync payloads already
/// use, so the code stays in that dense mode whatever the record holds.
class TransferInvite {
  /// Where the server can be reached, best first. More than one because the
  /// device cannot know which of its addresses the peer shares a network with.
  final List<String> addresses;

  final int port;

  /// Random per session, and the only way past the server's front door.
  final String token;

  /// The network to join first, when the sending device raised one for this
  /// transfer. Null for a transfer over a Wi-Fi both devices are already on.
  final HotspotCredentials? hotspot;

  /// When this invitation stops being accepted.
  final DateTime expiresAt;

  const TransferInvite({
    required this.addresses,
    required this.port,
    required this.token,
    required this.expiresAt,
    this.hotspot,
  });

  /// Builds an invitation valid for [kInviteLifetime] from now.
  factory TransferInvite.forNow({
    required List<String> addresses,
    required int port,
    required String token,
    HotspotCredentials? hotspot,
  }) => TransferInvite(
    addresses: addresses,
    port: port,
    token: token,
    hotspot: hotspot,
    expiresAt: DateTime.now().add(kInviteLifetime),
  );

  /// Whether this invitation is past [expiresAt].
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// The contents of the QR code that opens a transfer of the kind [prefix]
  /// names.
  String qrPayload(String prefix) {
    final record = <String, dynamic>{
      'a': addresses,
      'p': port,
      't': token,
      'x': expiresAt.millisecondsSinceEpoch,
      if (hotspot != null) 's': hotspot!.ssid,
      if (hotspot != null) 'k': hotspot!.passphrase,
    };
    return '$prefix${base45Encode(utf8.encode(jsonEncode(record)))}';
  }

  /// Parses what [qrPayload] produced, or null if [raw] is anything else,
  /// including a code of the other kind.
  ///
  /// Every malformed input is one null rather than a set of exceptions. This
  /// reads whatever a camera happened to see, so a code from a parcel label is
  /// an ordinary case and not an error worth telling apart.
  static TransferInvite? parse(String raw, {required String prefix}) {
    if (!raw.startsWith(prefix)) return null;

    final Map<String, dynamic> record;
    try {
      final decoded = jsonDecode(
        utf8.decode(base45Decode(raw.substring(prefix.length))),
      );
      if (decoded is! Map<String, dynamic>) return null;
      record = decoded;
    } catch (_) {
      return null;
    }

    final rawAddresses = record['a'];
    final port = record['p'];
    final token = record['t'];
    final expiresAt = record['x'];
    if (rawAddresses is! List || port is! int || token is! String) return null;
    if (expiresAt is! int) return null;
    if (port < 1 || port > 65535) return null;

    final addresses = rawAddresses.whereType<String>().toList();
    if (addresses.isEmpty || addresses.length > _kMaxParsedAddresses) {
      return null;
    }

    final ssid = record['s'];
    final passphrase = record['k'];

    return TransferInvite(
      addresses: addresses,
      port: port,
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
      hotspot: ssid is String && passphrase is String
          ? HotspotCredentials(ssid: ssid, passphrase: passphrase)
          : null,
    );
  }

  /// Every address as the URL the client asks for. In the order they should be
  /// tried.
  List<Uri> get endpoints => [
    for (final address in addresses) endpointAt(address),
  ];

  /// The URL this invitation's server answers on at [address].
  ///
  /// The client keeps the address that answered, never the whole URL: the token
  /// is what the invitation authorises, and remembering a URL would let a
  /// second call reach the server under a token it was not given.
  Uri endpointAt(String address) => Uri.parse('http://$address:$port/$token');
}
