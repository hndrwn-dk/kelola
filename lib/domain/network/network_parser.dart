import 'dart:convert';

import 'package:kelola/domain/network/network_snapshot.dart';

class NetworkParser {
  const NetworkParser();

  NetworkSnapshot parse(String stdout) {
    final addr = _section(stdout, 'ADDR');
    final route = _section(stdout, 'ROUTE');
    final ss = _section(stdout, 'SS');
    return NetworkSnapshot(
      interfaces: _parseAddr(addr),
      routes: _parseRoute(route),
      ports: _parseSs(ss),
    );
  }

  static String _section(String stdout, String name) {
    final startMark = '---$name---';
    final start = stdout.indexOf(startMark);
    if (start < 0) {
      return stdout;
    }
    var rest = stdout.substring(start + startMark.length);
    final next = rest.indexOf('\n---');
    if (next >= 0) {
      rest = rest.substring(0, next);
    }
    return rest.trim();
  }

  static List<NetInterface> _parseAddr(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('[')) {
      return _parseAddrJson(trimmed);
    }
    return _parseAddrText(raw);
  }

  static List<NetInterface> _parseAddrJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    final out = <NetInterface>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final map = item.cast<String, dynamic>();
      final name = (map['ifname'] ?? '').toString();
      if (name.isEmpty || _isLoopback(name, map['flags'])) {
        continue;
      }
      final addrs = <String>[];
      final info = map['addr_info'];
      if (info is List) {
        for (final a in info) {
          if (a is! Map) {
            continue;
          }
          final am = a.cast<String, dynamic>();
          final local = (am['local'] ?? '').toString();
          if (local.isEmpty) {
            continue;
          }
          final plen = am['prefixlen'];
          addrs.add(plen == null ? local : '$local/$plen');
        }
      }
      out.add(
        NetInterface(
          name: name,
          operstate: (map['operstate'] ?? '').toString(),
          addresses: addrs,
        ),
      );
    }
    return out;
  }

  static bool _isLoopback(String name, dynamic flags) {
    if (name == 'lo' || name.startsWith('lo:')) {
      return true;
    }
    if (flags is List) {
      return flags.map((f) => f.toString().toUpperCase()).contains('LOOPBACK');
    }
    return false;
  }

  static List<NetInterface> _parseAddrText(String raw) {
    final out = <NetInterface>[];
    String? name;
    var state = '';
    var loopback = false;
    var addrs = <String>[];

    void flush() {
      final n = name;
      if (n == null || loopback) {
        return;
      }
      out.add(NetInterface(name: n, operstate: state, addresses: List.of(addrs)));
    }

    final iface = RegExp(r'^\d+:\s+([^:]+):\s+<([^>]*)>.*\bstate\s+(\S+)');
    final inet = RegExp(r'^\s+inet6?\s+(\S+)');
    for (final line in raw.split('\n')) {
      final im = iface.firstMatch(line);
      if (im != null) {
        flush();
        name = im.group(1)!.split('@').first.trim();
        final flags = im.group(2)!.split(',');
        loopback = flags.contains('LOOPBACK') || name == 'lo';
        state = im.group(3)!;
        addrs = [];
        continue;
      }
      final am = inet.firstMatch(line);
      if (am != null && name != null) {
        addrs.add(am.group(1)!);
      }
    }
    flush();
    return out;
  }

  static List<NetRoute> _parseRoute(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('[')) {
      return _parseRouteJson(trimmed);
    }
    return _parseRouteText(raw);
  }

  static List<NetRoute> _parseRouteJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    final out = <NetRoute>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final map = item.cast<String, dynamic>();
      final dst = (map['dst'] ?? '').toString();
      if (dst.isEmpty) {
        continue;
      }
      final metric = map['metric'];
      out.add(
        NetRoute(
          dst: dst,
          gateway: _str(map['gateway']),
          dev: _str(map['dev']),
          metric: metric is int ? metric : int.tryParse('$metric'),
        ),
      );
    }
    return out;
  }

  static List<NetRoute> _parseRouteText(String raw) {
    final out = <NetRoute>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) {
        continue;
      }
      final parts = t.split(RegExp(r'\s+'));
      if (parts.isEmpty) {
        continue;
      }
      String? gateway;
      String? dev;
      int? metric;
      for (var i = 0; i < parts.length; i++) {
        if (parts[i] == 'via' && i + 1 < parts.length) {
          gateway = parts[i + 1];
        }
        if (parts[i] == 'dev' && i + 1 < parts.length) {
          dev = parts[i + 1];
        }
        if (parts[i] == 'metric' && i + 1 < parts.length) {
          metric = int.tryParse(parts[i + 1]);
        }
      }
      out.add(
        NetRoute(dst: parts.first, gateway: gateway, dev: dev, metric: metric),
      );
    }
    return out;
  }

  static List<ListenPort> _parseSs(String raw) {
    final out = <ListenPort>[];
    final procRe = RegExp(r'users:\(\("([^"]+)",pid=(\d+)');
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('Netid') || t.startsWith('State')) {
        continue;
      }
      final parts = t.split(RegExp(r'\s+'));
      if (parts.length < 5) {
        continue;
      }
      final proto = parts[0].toLowerCase();
      if (proto != 'tcp' && proto != 'udp' && proto != 'sctp') {
        continue;
      }
      final state = parts[1];
      var local = '';
      for (final p in parts) {
        if (p.contains(':') && !p.startsWith('users:')) {
          local = p;
          break;
        }
      }
      if (local.isEmpty) {
        continue;
      }
      final pm = procRe.firstMatch(t);
      out.add(
        ListenPort(
          proto: proto,
          local: local,
          state: state,
          process: pm?.group(1) ?? '',
          pid: pm == null ? null : int.tryParse(pm.group(2)!),
        ),
      );
    }
    return out;
  }

  static String? _str(dynamic raw) {
    if (raw == null) {
      return null;
    }
    final s = raw.toString();
    return s.isEmpty ? null : s;
  }
}
