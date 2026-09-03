import 'dart:convert';

import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/firewall/firewall_snapshot.dart';

class FirewallParser {
  const FirewallParser();

  FirewallSnapshot parse({
    required FirewallBackend backend,
    required String stdout,
  }) {
    return switch (backend) {
      FirewallBackend.firewalld => _firewalld(stdout),
      FirewallBackend.ufw => _ufw(stdout),
      FirewallBackend.nftables => _nft(stdout),
      FirewallBackend.iptables => _iptables(stdout),
      FirewallBackend.none => const FirewallSnapshot(
          backend: FirewallBackend.none,
          rules: [],
        ),
    };
  }

  FirewallSnapshot _firewalld(String stdout) {
    final list = _section(stdout, 'LIST');
    final body = list.isEmpty ? stdout : list;
    String? zone;
    String? defaultZone = _section(stdout, 'DEFAULT').trim().split('\n').first.trim();
    if (defaultZone.isEmpty) {
      defaultZone = null;
    }
    final rules = <FirewallRule>[];
    for (final raw in body.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (!line.startsWith(' ') &&
          !line.startsWith('\t') &&
          trimmed.contains('(') &&
          !trimmed.contains(':')) {
        zone = trimmed.split(' ').first;
        continue;
      }
      final t = trimmed;
      if (t.startsWith('services:')) {
        final rest = t.substring('services:'.length).trim();
        for (final svc in rest.split(RegExp(r'\s+'))) {
          if (svc.isEmpty) {
            continue;
          }
          rules.add(
            FirewallRule(
              id: 'svc:$svc',
              summary: svc,
              service: svc,
              action: 'allow',
              zone: zone,
            ),
          );
        }
      } else if (t.startsWith('ports:')) {
        final rest = t.substring('ports:'.length).trim();
        for (final p in rest.split(RegExp(r'\s+'))) {
          if (p.isEmpty) {
            continue;
          }
          rules.add(
            FirewallRule(
              id: 'port:$p',
              summary: p,
              port: p,
              action: 'allow',
              zone: zone,
            ),
          );
        }
      } else if (t.startsWith('rich rules:')) {
        continue;
      } else if (t.startsWith('rule ') || t.contains('rule family=')) {
        rules.add(
          FirewallRule(
            id: 'rich:${rules.length}',
            summary: t,
            action: t.contains('drop') || t.contains('reject') ? 'deny' : 'allow',
            zone: zone,
          ),
        );
      }
    }
    return FirewallSnapshot(
      backend: FirewallBackend.firewalld,
      rules: rules,
      defaultZone: defaultZone ?? zone,
    );
  }

  FirewallSnapshot _ufw(String stdout) {
    String? policy;
    final rules = <FirewallRule>[];
    var inTable = false;
    for (final raw in stdout.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('default:')) {
        policy = trimmed.substring('default:'.length).trim();
        continue;
      }
      if (trimmed.startsWith('--')) {
        inTable = true;
        continue;
      }
      if (trimmed.toLowerCase().startsWith('to ') &&
          trimmed.toLowerCase().contains('action')) {
        continue;
      }
      if (!inTable) {
        continue;
      }
      if (trimmed.isEmpty) {
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s{2,}'));
      if (parts.length < 2) {
        continue;
      }
      final to = parts[0].trim();
      final action = parts.length > 1 ? parts[1].trim() : '';
      final from = parts.length > 2 ? parts[2].trim() : '';
      final id = '$to $action $from';
      final port = _ufwPort(to);
      rules.add(
        FirewallRule(
          id: id,
          summary: from.isEmpty ? '$to $action' : '$to $action $from',
          port: port,
          service: to.toLowerCase().contains('ssh') ? 'ssh' : null,
          action: action.toLowerCase().contains('deny') ||
                  action.toLowerCase().contains('reject')
              ? 'deny'
              : 'allow',
        ),
      );
    }
    return FirewallSnapshot(
      backend: FirewallBackend.ufw,
      rules: rules,
      defaultPolicy: policy,
    );
  }

  FirewallSnapshot _nft(String stdout) {
    final jsonText = _jsonBlob(stdout);
    if (jsonText.isEmpty) {
      return const FirewallSnapshot(
        backend: FirewallBackend.nftables,
        rules: [],
      );
    }
    final decoded = jsonDecode(jsonText);
    final rules = <FirewallRule>[];
    if (decoded is Map && decoded['nftables'] is List) {
      for (final item in decoded['nftables'] as List) {
        if (item is! Map) {
          continue;
        }
        final rule = item['rule'];
        if (rule is! Map) {
          continue;
        }
        final family = '${rule['family'] ?? ''}';
        final table = '${rule['table'] ?? ''}';
        final chain = '${rule['chain'] ?? ''}';
        final handle = '${rule['handle'] ?? ''}';
        final expr = rule['expr'];
        final blob = jsonEncode(rule);
        final port = _nftPort(expr, blob);
        final action = blob.contains('"drop"') || blob.contains('"reject"')
            ? 'deny'
            : blob.contains('"accept"')
                ? 'allow'
                : null;
        final summary = [
          if (chain.isNotEmpty) chain,
          ?port,
          ?action,
        ].join(' ');
        rules.add(
          FirewallRule(
            id: handle.isEmpty ? '$family:$table:$chain:${rules.length}' : handle,
            summary: summary.isEmpty ? blob : summary,
            port: port,
            action: action,
            chain: chain.isEmpty ? null : chain,
            handle: handle.isEmpty ? null : handle,
          ),
        );
      }
    }
    return FirewallSnapshot(
      backend: FirewallBackend.nftables,
      rules: rules,
    );
  }

  FirewallSnapshot _iptables(String stdout) {
    final rules = <FirewallRule>[];
    String chain = '';
    for (final raw in stdout.split('\n')) {
      final line = raw.trim();
      if (line.startsWith(':') && line.contains(' ')) {
        chain = line.substring(1).split(' ').first;
        continue;
      }
      if (!line.startsWith('-A ')) {
        continue;
      }
      final rest = line.substring(3);
      final chainName = rest.split(' ').first;
      final port = _iptablesPort(line);
      rules.add(
        FirewallRule(
          id: '${rules.length}:$line',
          summary: rest,
          port: port,
          action: line.contains('DROP') || line.contains('REJECT')
              ? 'deny'
              : line.contains('ACCEPT')
                  ? 'allow'
                  : null,
          chain: chainName.isEmpty ? chain : chainName,
        ),
      );
    }
    return FirewallSnapshot(
      backend: FirewallBackend.iptables,
      rules: rules,
      readOnly: true,
    );
  }

  static String? _ufwPort(String to) {
    final m = RegExp(r'(\d+)(?:/(tcp|udp))?', caseSensitive: false).firstMatch(to);
    if (m == null) {
      return null;
    }
    final proto = m.group(2);
    return proto == null ? m.group(1) : '${m.group(1)}/${proto.toLowerCase()}';
  }

  static String? _nftPort(Object? _, String blob) {
    final i = blob.indexOf('"dport"');
    if (i < 0) {
      return null;
    }
    final rest = blob.substring(i);
    final value = RegExp(r'"value"\s*:\s*(\d+)').firstMatch(rest);
    if (value != null) {
      return '${value.group(1)}/tcp';
    }
    final right = RegExp(r'"right"\s*:\s*(\d+)').firstMatch(rest);
    if (right != null) {
      return '${right.group(1)}/tcp';
    }
    return null;
  }

  static String? _iptablesPort(String line) {
    final m = RegExp(r'--dport(?:s)?\s+(\d+)').firstMatch(line);
    if (m != null) {
      final proto = line.contains('-p udp') ? 'udp' : 'tcp';
      return '${m.group(1)}/$proto';
    }
    return null;
  }

  static String _section(String stdout, String name) {
    final marker = '---$name---';
    final i = stdout.indexOf(marker);
    if (i < 0) {
      return '';
    }
    final start = i + marker.length;
    final next = stdout.indexOf('\n---', start);
    if (next < 0) {
      return stdout.substring(start);
    }
    return stdout.substring(start, next);
  }

  static String _jsonBlob(String stdout) {
    final i = stdout.indexOf('{');
    if (i < 0) {
      return '';
    }
    return stdout.substring(i);
  }
}
