import 'dart:io';

// ── Interface classification ──────────────────────────────────────────────────

/// Interface name prefixes that carry a local network a peer can reach, best
/// first.
///
/// `ap` and `swlan` are the access point interfaces a phone raises when it
/// hosts a network, `wlan` is Android's Wi-Fi, `en` is Apple's, and the wired
/// names are there for the desktop builds the tests run on.
const List<String> _kPreferredInterfaces = [
  'ap',
  'swlan',
  'wlan',
  'en',
  'bridge',
  'eth',
];

/// Interface name prefixes that never carry a peer on the local network.
///
/// Mobile data (`rmnet`, `ccmni`, `pdp_ip`), tunnels (`utun`, `tun`, `ipsec`,
/// `ppp`) and the virtual leftovers. Handing one of these out as the address to
/// connect to is what made a connection code look right and lead nowhere: the
/// old lookup preferred `en*`, which no Android device has, and then took
/// whatever came first.
const List<String> _kExcludedInterfaces = [
  'rmnet',
  'ccmni',
  'pdp_ip',
  'rndis',
  'utun',
  'tun',
  'ipsec',
  'ppp',
  'tap',
  'dummy',
  'lo',
  'p2p',
];

/// Subnets a phone's own hotspot hands out, in the order they are trusted.
///
/// An address from one of these is the most certain of all: the peer is on a
/// network this device or the other one raised, so nothing sits between them.
const List<String> _kHotspotSubnets = [
  '192.168.49.', // Android LocalOnlyHotspot
  '192.168.43.', // Android tethering
  '172.20.10.', // iOS personal hotspot
];

/// How many addresses a connection code carries at most.
///
/// Every candidate costs the receiver one round of probing and the QR code a
/// few modules. Three covers a phone on Wi-Fi with a hotspot up; past that the
/// extra addresses are guesses rather than candidates.
const int kMaxTransferAddresses = 3;

// ── Lookup ────────────────────────────────────────────────────────────────────

/// One network interface reduced to what the ranking looks at.
///
/// The ranking takes these rather than `NetworkInterface` so it can be
/// exercised without a machine that happens to be on the right kind of network.
typedef LocalInterface = ({String name, List<String> addresses});

/// Every IPv4 address a peer on the local network could reach this device on,
/// best first, at most [kMaxTransferAddresses] of them.
///
/// Empty when the device is on no usable network. That is a real answer and has
/// to be reported as one: the lookup this replaced fell back to `127.0.0.1`,
/// which produced a connection code that parsed, scanned and could never
/// connect.
Future<List<String>> localTransferAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    return rankTransferAddresses([
      for (final iface in interfaces)
        (
          name: iface.name,
          addresses: [for (final addr in iface.addresses) addr.address],
        ),
    ]);
  } catch (_) {
    return const [];
  }
}

/// The ranking half of [localTransferAddresses].
///
/// Loopback needs no test of its own here: `127.0.0.1` is not in any of the
/// private ranges [_isPrivateV4] accepts, so it falls out with every other
/// address a peer cannot reach.
List<String> rankTransferAddresses(List<LocalInterface> interfaces) {
  final candidates = <({String address, int rank})>[];

  for (final iface in interfaces) {
    final interfaceRank = _interfaceRank(iface.name);
    if (interfaceRank == null) continue;

    for (final address in iface.addresses) {
      if (!_isPrivateV4(address)) continue;
      candidates.add((
        address: address,
        rank: _hotspotRank(address) ?? (100 + interfaceRank),
      ));
    }
  }

  candidates.sort((a, b) => a.rank.compareTo(b.rank));

  final seen = <String>{};
  final ordered = <String>[];
  for (final candidate in candidates) {
    if (!seen.add(candidate.address)) continue;
    ordered.add(candidate.address);
    if (ordered.length == kMaxTransferAddresses) break;
  }
  return ordered;
}

/// Where [name] sits in [_kPreferredInterfaces], or null when the interface is
/// excluded or unknown.
///
/// An unknown name is dropped rather than ranked last. A name nobody listed is
/// far more likely to be a tunnel this list has not met than a Wi-Fi adapter,
/// and the address range check below is not enough on its own: a VPN happily
/// hands out addresses from the private ranges.
int? _interfaceRank(String name) {
  final lower = name.toLowerCase();
  for (final excluded in _kExcludedInterfaces) {
    if (lower.startsWith(excluded)) return null;
  }
  for (var i = 0; i < _kPreferredInterfaces.length; i++) {
    if (lower.startsWith(_kPreferredInterfaces[i])) return i;
  }
  return null;
}

/// Where [address] sits in [_kHotspotSubnets], or null when it is an ordinary
/// local address.
int? _hotspotRank(String address) {
  for (var i = 0; i < _kHotspotSubnets.length; i++) {
    if (address.startsWith(_kHotspotSubnets[i])) return i;
  }
  return null;
}

/// Whether [address] is in one of the three IPv4 ranges reserved for private
/// networks.
///
/// The carrier grade range `100.64/10` is deliberately not among them: it looks
/// private, and an address from it belongs to the mobile network rather than to
/// anything the peer can reach.
bool _isPrivateV4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;
  final first = int.tryParse(parts[0]);
  final second = int.tryParse(parts[1]);
  if (first == null || second == null) return false;

  if (first == 10) return true;
  if (first == 192 && second == 168) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  return false;
}
