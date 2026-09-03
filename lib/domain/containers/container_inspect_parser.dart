import 'dart:convert';

import 'package:kelola/domain/containers/container_detail.dart';
import 'package:kelola/domain/redaction/redact.dart';

class ContainerInspectParser {
  const ContainerInspectParser();

  ContainerDetail parse(String stdout, String stderr, int exitCode) {
    final inspectRaw = _section(stdout, 'INSPECT');
    final statsRaw = _section(stdout, 'STATS');
    final logs = _section(stdout, 'LOGS');
    var name = '';
    var env = <String>[];
    var mounts = <String>[];
    var networks = <String>[];
    var restartPolicy = '';

    final inspect = _firstObject(inspectRaw);
    if (inspect != null) {
      name = (inspect['Name'] ?? inspect['Names'] ?? '').toString();
      name = name.replaceFirst(RegExp(r'^/'), '');
      final config = inspect['Config'];
      if (config is Map) {
        final rawEnv = config['Env'];
        if (rawEnv is List) {
          env = rawEnv.map((e) => e.toString()).toList();
        }
      }
      restartPolicy = _restartPolicy(inspect);
      mounts = _mounts(inspect);
      networks = _networks(inspect);
    }

    var cpuPerc = '';
    var memUsage = '';
    final stats = _firstObject(statsRaw);
    if (stats != null) {
      cpuPerc = (stats['CPUPerc'] ?? stats['cpu_percent'] ?? '').toString();
      memUsage = (stats['MemUsage'] ?? stats['mem_usage'] ?? '').toString();
      if (name.isEmpty) {
        name = (stats['Name'] ?? '').toString().replaceFirst(RegExp(r'^/'), '');
      }
    }

    return ContainerDetail(
      name: name,
      env: redactEnv(env),
      mounts: mounts,
      networks: networks,
      restartPolicy: restartPolicy,
      cpuPerc: cpuPerc,
      memUsage: memUsage,
      logs: logs,
    );
  }

  String _restartPolicy(Map<String, dynamic> inspect) {
    final host = inspect['HostConfig'];
    if (host is! Map) {
      return '';
    }
    final policy = host['RestartPolicy'] ?? host['restart_policy'];
    if (policy is Map) {
      return (policy['Name'] ?? policy['name'] ?? '').toString();
    }
    return policy?.toString() ?? '';
  }

  List<String> _mounts(Map<String, dynamic> inspect) {
    final out = <String>[];
    final mounts = inspect['Mounts'];
    if (mounts is List) {
      for (final item in mounts) {
        if (item is! Map) {
          continue;
        }
        final src = (item['Source'] ?? item['source'] ?? '').toString();
        final dst =
            (item['Destination'] ?? item['destination'] ?? '').toString();
        if (src.isEmpty && dst.isEmpty) {
          continue;
        }
        if (src.isEmpty) {
          out.add(dst);
        } else if (dst.isEmpty) {
          out.add(src);
        } else {
          out.add('$src \u2192 $dst');
        }
      }
    }
    return out;
  }

  List<String> _networks(Map<String, dynamic> inspect) {
    final settings = inspect['NetworkSettings'];
    if (settings is! Map) {
      return const [];
    }
    final nets = settings['Networks'];
    if (nets is! Map) {
      return const [];
    }
    return nets.keys.map((k) => k.toString()).toList();
  }

  Map<String, dynamic>? _firstObject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        return (decoded.first as Map).cast<String, dynamic>();
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } on FormatException {
      for (final line in trimmed.split('\n')) {
        final t = line.trim();
        if (!t.startsWith('{')) {
          continue;
        }
        try {
          final decoded = jsonDecode(t);
          if (decoded is Map) {
            return decoded.cast<String, dynamic>();
          }
        } on FormatException {
          continue;
        }
      }
    }
    return null;
  }

  String _section(String stdout, String name) {
    final marker = '---$name---';
    final i = stdout.indexOf(marker);
    if (i < 0) {
      return '';
    }
    final start = i + marker.length;
    final next = RegExp(r'^---[A-Z_]+---\s*$', multiLine: true)
        .firstMatch(stdout.substring(start));
    final end = next == null ? stdout.length : start + next.start;
    return stdout.substring(start, end).replaceAll('\r', '').trim();
  }
}
