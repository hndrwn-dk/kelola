import 'dart:io';

/// Whether an LLM base URI is treated as on-LAN / loopback (no outbound preview)
/// vs public (payload leaves the device over the wider internet).
enum EndpointLocality { local, public }

/// Pure string classification. No DNS. No network I/O.
EndpointLocality classifyEndpoint(Uri? uri) {
  if (uri == null) {
    return EndpointLocality.public;
  }
  var host = uri.host.trim();
  if (host.isEmpty) {
    return EndpointLocality.public;
  }
  host = host.toLowerCase();
  if (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  if (host.isEmpty) {
    return EndpointLocality.public;
  }

  if (_isLocalHostname(host)) {
    return EndpointLocality.local;
  }

  final mapped = _ipv4MappedFromIpv6(host);
  if (mapped != null) {
    return _classifyIpv4(mapped)
        ? EndpointLocality.local
        : EndpointLocality.public;
  }

  final addr = InternetAddress.tryParse(host);
  if (addr != null) {
    if (addr.type == InternetAddressType.IPv4) {
      return _classifyIpv4(addr.rawAddress)
          ? EndpointLocality.local
          : EndpointLocality.public;
    }
    if (addr.type == InternetAddressType.IPv6) {
      return _classifyIpv6(addr.rawAddress)
          ? EndpointLocality.local
          : EndpointLocality.public;
    }
  }

  // Single-label or any other hostname: public (no DNS to check).
  return EndpointLocality.public;
}

bool isLocalEndpoint(Uri? uri) =>
    classifyEndpoint(uri) == EndpointLocality.local;

bool _isLocalHostname(String host) {
  if (host == 'localhost' || host.endsWith('.localhost')) {
    return true;
  }
  const suffixes = ['.local', '.lan', '.home.arpa', '.internal'];
  for (final s in suffixes) {
    if (host == s.substring(1) || host.endsWith(s)) {
      // bare "local" / "lan" etc. are single-label → public; only suffixes.
      if (host == s.substring(1)) {
        return false;
      }
      return true;
    }
  }
  return false;
}

/// Returns 4-byte IPv4 if [host] is IPv4-mapped IPv6 (`::ffff:a.b.c.d`).
List<int>? _ipv4MappedFromIpv6(String host) {
  final addr = InternetAddress.tryParse(host);
  if (addr == null || addr.type != InternetAddressType.IPv6) {
    return null;
  }
  final b = addr.rawAddress;
  if (b.length != 16) {
    return null;
  }
  // ::ffff:0:0/96 → bytes 0..9 zero, 10..11 0xff, 12..15 IPv4
  for (var i = 0; i < 10; i++) {
    if (b[i] != 0) {
      return null;
    }
  }
  if (b[10] != 0xff || b[11] != 0xff) {
    return null;
  }
  return b.sublist(12, 16);
}

bool _classifyIpv4(List<int> b) {
  if (b.length != 4) {
    return false;
  }
  final a = b[0];
  final c = b[1];
  // 0.0.0.0 unspecified → public
  if (a == 0 && c == 0 && b[2] == 0 && b[3] == 0) {
    return false;
  }
  // 127.0.0.0/8
  if (a == 127) {
    return true;
  }
  // 10.0.0.0/8
  if (a == 10) {
    return true;
  }
  // 172.16.0.0/12
  if (a == 172 && c >= 16 && c <= 31) {
    return true;
  }
  // 192.168.0.0/16
  if (a == 192 && c == 168) {
    return true;
  }
  // 169.254.0.0/16
  if (a == 169 && c == 254) {
    return true;
  }
  // 100.64.0.0/10
  if (a == 100 && c >= 64 && c <= 127) {
    return true;
  }
  return false;
}

bool _classifyIpv6(List<int> b) {
  if (b.length != 16) {
    return false;
  }
  // :: unspecified → public
  if (b.every((e) => e == 0)) {
    return false;
  }
  // ::1 loopback
  var isLoop = true;
  for (var i = 0; i < 15; i++) {
    if (b[i] != 0) {
      isLoop = false;
      break;
    }
  }
  if (isLoop && b[15] == 1) {
    return true;
  }
  // fc00::/7 ULA (fc00::/8 and fd00::/8)
  if ((b[0] & 0xfe) == 0xfc) {
    return true;
  }
  // fe80::/10 link-local
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) {
    return true;
  }
  return false;
}
