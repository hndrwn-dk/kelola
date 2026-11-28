import 'dart:convert';

import 'package:kelola/domain/argocd/argo_app.dart';
import 'package:kelola/domain/k8s/openshift_health_parser.dart'
    show ocpErrorReason;

/// M49 §2a–§2c. Parses `ArgoAppsProbe` stdout:
///
/// ```
/// [---READER_DENIED---]
/// ---APPS---
/// <kubectl get applications.argoproj.io -A -o json, or nothing>
/// [---APPS_ERR---
///  KELOLA_ERR <stderr lines>]
/// ```
///
/// or `---NO_KUBECTL---` alone. Reads only the §2b fields by explicit key;
/// Helm, plugin, kustomize and directory inputs are never touched. The raw
/// stdout is discarded: an error is built only from the `---APPS_ERR---`
/// section, so no JSON body text can reach `error`. Junk never throws.
ArgoApps parseArgoApps(String stdout, {required DateTime readAt}) {
  final lines = stdout.replaceAll('\r\n', '\n').split('\n');
  final appsAt = _markerLine(lines, 'APPS', 0);
  final head = appsAt < 0 ? lines : lines.sublist(0, appsAt);
  final readerDenied = head.any((l) => l.trim() == '---READER_DENIED---');

  ArgoApps fail(String error) => ArgoApps(
        apps: const [],
        error: error,
        readAt: readAt,
        readerDenied: readerDenied,
      );

  if (head.any((l) => l.trim() == '---NO_KUBECTL---')) {
    return fail('no kubectl');
  }
  if (appsAt < 0) {
    return fail('no output');
  }

  final body = _sectionBody(lines, appsAt);
  final errAt = _markerLine(lines, 'APPS_ERR', appsAt + 1);
  final errBody = errAt < 0 ? null : _sectionBody(lines, errAt);

  final json = _jsonMap(body);
  final items = json?['items'];
  if (items is! List) {
    final reason = errBody == null ? '' : ocpErrorReason(errBody);
    return fail(reason.isEmpty ? 'unreadable output' : reason);
  }

  final apps = <ArgoApp>[
    for (final item in items)
      if (item is Map) _app(item),
  ];
  return ArgoApps(apps: apps, readAt: readAt, readerDenied: readerDenied);
}

/// Drops credentials from a repo URL before it is stored or shown.
///
/// - `scheme://` (http, https, oci, …): credentials before `@`, query and
///   fragment go. Only an `@` inside the authority counts.
/// - `ssh://`: keeps the user name only (`git:pw@` → `git@`).
/// - scp-like `user:pw@host:path`: keeps `user@host:path`.
/// - anything else holding `@`: everything up to the last `@` goes.
String stripRepoCredentials(String url) {
  final s = url.trim();
  if (s.isEmpty) {
    return s;
  }
  final scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*)://').firstMatch(s);
  if (scheme != null) {
    final prefix = s.substring(0, scheme.end);
    final name = scheme.group(1)!.toLowerCase();
    final isSsh = name == 'ssh' || name == 'git+ssh';
    var rest = s.substring(scheme.end);
    var user = '';
    final authEnd = rest.indexOf(RegExp('[/?#]'));
    final at = (authEnd < 0 ? rest : rest.substring(0, authEnd))
        .lastIndexOf('@');
    if (at >= 0) {
      if (isSsh) {
        user = rest.substring(0, at).split(RegExp('[:@]')).first;
      }
      rest = rest.substring(at + 1);
    }
    final cut = rest.indexOf(RegExp('[?#]'));
    if (cut >= 0) {
      rest = rest.substring(0, cut);
    }
    return user.isEmpty ? '$prefix$rest' : '$prefix$user@$rest';
  }
  final at = s.lastIndexOf('@');
  if (at < 0) {
    return s;
  }
  final before = s.substring(0, at);
  final after = s.substring(at + 1);
  final scpLike =
      !s.contains('//') && after.contains(':') && !before.contains('/');
  if (scpLike) {
    final user = before.split(RegExp('[:@]')).first;
    return user.isEmpty ? after : '$user@$after';
  }
  return after;
}

/// 7-character commit SHA; tags, branches and chart versions unchanged.
String shortRevision(String rev) => shortArgoRevision(rev);

/// Scheme, authority, path, then the rest of the token (`?…` / `#…`).
final _urlInText = RegExp(
  r'([A-Za-z][A-Za-z0-9+.\-]*://)([^\s/?#]*)([^\s?#]*)(\S*)',
);

/// Drops credentials from every `scheme://…@` URL inside free text (Argo CD
/// messages can echo a repo URL), by the same rule as
/// [stripRepoCredentials]: ssh keeps its user name, and an http(s) URL also
/// loses its query and fragment (they can carry an access key).
String redactUrlCredentials(String text) {
  return text.replaceAllMapped(_urlInText, (m) {
    final prefix = m.group(1)!;
    final authority = m.group(2)!;
    final path = m.group(3)!;
    final name = prefix.substring(0, prefix.length - 3).toLowerCase();
    final tail = name == 'http' || name == 'https' ? '' : m.group(4)!;
    final at = authority.lastIndexOf('@');
    if (at < 0) {
      return '$prefix$authority$path$tail';
    }
    final host = authority.substring(at + 1);
    if (name == 'ssh' || name == 'git+ssh') {
      final user = authority.substring(0, at).split(RegExp('[:@]')).first;
      if (user.isNotEmpty) {
        return '$prefix$user@$host$path$tail';
      }
    }
    return '$prefix$host$path$tail';
  });
}

ArgoApp _app(Map<dynamic, dynamic> raw) {
  final meta = _map(raw['metadata']);
  final spec = _map(raw['spec']);
  final status = _map(raw['status']);

  final sources = <ArgoSource>[];
  final multi = spec['sources'];
  if (multi is List && multi.isNotEmpty) {
    for (final s in multi) {
      if (s is Map) {
        sources.add(_source(s));
      }
    }
  } else if (spec['source'] is Map) {
    sources.add(_source(spec['source'] as Map));
  }

  final dest = _map(spec['destination']);
  final server = _str(dest['server']);

  final autoRaw = _map(spec['syncPolicy'])['automated'];
  final auto = _map(autoRaw);
  final automated = autoRaw is Map && auto['enabled'] != false;

  final syncMap = _map(status['sync']);
  final revisions = <String>[
    for (final r in _list(syncMap['revisions']))
      if (r is String && r.isNotEmpty) r,
  ];
  if (revisions.isEmpty && _str(syncMap['revision']).isNotEmpty) {
    revisions.add(_str(syncMap['revision']));
  }

  final healthMap = _map(status['health']);
  final op = _map(status['operationState']);
  final opMessage = _str(op['message']);

  return ArgoApp(
    name: _str(meta['name']),
    namespace: _str(meta['namespace']),
    // Argo CD treats an empty project as `default`; say so everywhere.
    project: _str(spec['project']).isEmpty ? 'default' : _str(spec['project']),
    sources: sources,
    destServer: server.isNotEmpty ? server : _str(dest['name']),
    destNamespace: _str(dest['namespace']),
    sync: _sync(syncMap['status']),
    health: _health(healthMap['status']),
    syncedRevisions: revisions,
    automated: automated,
    prune: automated && auto['prune'] == true,
    selfHeal: automated && auto['selfHeal'] == true,
    opPhase: _phase(op['phase']),
    opMessage: opMessage.isEmpty ? null : redactUrlCredentials(opMessage),
    opStartedAt: _time(op['startedAt']),
    opFinishedAt: _time(op['finishedAt']),
    conditions: [
      for (final c in _list(status['conditions']))
        if (c is Map)
          ArgoCondition(
            type: _str(c['type']),
            message: redactUrlCredentials(_str(c['message'])),
          ),
    ],
    resources: [
      for (final r in _list(status['resources']))
        if (r is Map) _resource(r),
    ],
    history: _history(status['history']),
    reconciledAt: _time(status['reconciledAt']),
  );
}

/// Reads repoURL, path, chart and targetRevision only.
ArgoSource _source(Map<dynamic, dynamic> raw) {
  final repo = stripRepoCredentials(_str(raw['repoURL']));
  final path = _str(raw['path']);
  final chart = _str(raw['chart']);
  final target = _str(raw['targetRevision']);
  final kind = repo.toLowerCase().startsWith('oci://')
      ? 'oci'
      : (chart.isNotEmpty ? 'helm' : 'git');
  return ArgoSource(
    repoUrl: repo,
    path: path.isEmpty ? null : path,
    chart: chart.isEmpty ? null : chart,
    targetRevision: target.isEmpty ? 'HEAD' : target,
    kind: kind,
  );
}

ArgoResource _resource(Map<dynamic, dynamic> raw) {
  final health = _map(raw['health']);
  final message = redactUrlCredentials(_str(health['message']));
  return ArgoResource(
    group: _str(raw['group']),
    kind: _str(raw['kind']),
    namespace: _str(raw['namespace']),
    name: _str(raw['name']),
    sync: _sync(raw['status']),
    health: _health(health['status']),
    healthMessage: message.isEmpty ? null : message,
    requiresPruning: raw['requiresPruning'] == true,
  );
}

/// Newest first: highest id first, later entries first on a tie.
List<ArgoHistoryEntry> _history(Object? raw) {
  final out = <(int, ArgoHistoryEntry)>[];
  var order = 0;
  for (final h in _list(raw)) {
    if (h is! Map) {
      continue;
    }
    var rev = _str(h['revision']);
    if (rev.isEmpty) {
      for (final r in _list(h['revisions'])) {
        if (r is String && r.isNotEmpty) {
          rev = r;
          break;
        }
      }
    }
    final id = h['id'];
    out.add((
      order++,
      ArgoHistoryEntry(
        id: id is int
            ? id
            : (id is double && id.isFinite ? id.toInt() : 0),
        revision: shortArgoRevision(rev),
        deployedAt: _time(h['deployedAt']),
      ),
    ));
  }
  out.sort((a, b) {
    final byId = b.$2.id.compareTo(a.$2.id);
    return byId != 0 ? byId : b.$1.compareTo(a.$1);
  });
  return [for (final e in out) e.$2];
}

ArgoSync _sync(Object? v) => switch (v) {
      'Synced' => ArgoSync.synced,
      'OutOfSync' => ArgoSync.outOfSync,
      _ => ArgoSync.unknown,
    };

ArgoHealth _health(Object? v) => switch (v) {
      'Healthy' => ArgoHealth.healthy,
      'Progressing' => ArgoHealth.progressing,
      'Degraded' => ArgoHealth.degraded,
      'Suspended' => ArgoHealth.suspended,
      'Missing' => ArgoHealth.missing,
      _ => ArgoHealth.unknown,
    };

ArgoOpPhase _phase(Object? v) => switch (v) {
      'Running' => ArgoOpPhase.running,
      'Succeeded' => ArgoOpPhase.succeeded,
      'Failed' => ArgoOpPhase.failed,
      'Error' => ArgoOpPhase.error,
      'Terminating' => ArgoOpPhase.terminating,
      _ => ArgoOpPhase.none,
    };

final _marker = RegExp(r'^---[A-Z0-9_]+---$');

/// Index of the whole line `---<name>---` at or after [from], or -1. Markers
/// are whole lines; `-o json` escapes newlines, so a JSON string can't fake
/// one.
int _markerLine(List<String> lines, String name, int from) {
  final tag = '---$name---';
  for (var i = from; i < lines.length; i++) {
    if (lines[i].trim() == tag) {
      return i;
    }
  }
  return -1;
}

String _sectionBody(List<String> lines, int markerAt) {
  final out = <String>[];
  for (var i = markerAt + 1; i < lines.length; i++) {
    if (_marker.hasMatch(lines[i].trim())) {
      break;
    }
    out.add(lines[i]);
  }
  return out.join('\n');
}

Map<String, dynamic>? _jsonMap(String raw) {
  final start = raw.indexOf('{');
  if (start < 0) {
    return null;
  }
  final end = raw.lastIndexOf('}');
  if (end < start) {
    return null;
  }
  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } on FormatException {
    return null;
  }
  return null;
}

Map<dynamic, dynamic> _map(Object? v) => v is Map ? v : const {};

List<Object?> _list(Object? v) => v is List ? v : const [];

String _str(Object? v) => v is String ? v : '';

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;
