/// M7 / diagnostic-pack redaction table. One implementation for LLM,
/// diagnostic packs, and container env display.
String redactText(
  String text, {
  List<String> hostnames = const [],
  List<String> usernames = const [],
}) {
  var out = text;
  final hosts = _Indexer('HOST');
  final users = _Indexer('USER');
  final emails = _Indexer('EMAIL');
  final macs = _Indexer('MAC');
  final ips = _Indexer('IP');

  for (final h in _sortedUnique(hostnames)) {
    out = hosts.replaceLiteral(out, h);
  }
  for (final u in _sortedUnique(usernames)) {
    out = users.replaceLiteral(out, u);
  }
  out = emails.replaceRegex(
    out,
    RegExp(r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b'),
  );
  out = macs.replaceRegex(
    out,
    RegExp(r'\b[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\b'),
  );
  out = ips.replaceRegex(
    out,
    RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
  );
  out = ips.replaceRegex(
    out,
    RegExp(
      r'(?:[0-9A-Fa-f]{1,4}:)*[0-9A-Fa-f]{1,4}::(?:[0-9A-Fa-f]{1,4}:)*[0-9A-Fa-f]{0,4}',
    ),
  );

  out = out.replaceAllMapped(
    RegExp(
      r'([A-Za-z0-9_]*?(?:[Pp]assword|[Tt]oken|[Ss]ecret)[A-Za-z0-9_]*\s*=\s*)[^\s]+',
    ),
    (m) => '${m.group(1)}<REDACTED>',
  );
  out = out.replaceAllMapped(
    RegExp(r'(Bearer\s+)\S+', caseSensitive: false),
    (m) => '${m.group(1)}<REDACTED>',
  );
  out = out.replaceAllMapped(
    RegExp(r'[A-Za-z0-9+/]{40,}={0,2}'),
    (m) {
      final v = m.group(0)!;
      if (v.contains('<') || v.contains('>')) {
        return v;
      }
      return '<REDACTED>';
    },
  );
  return out;
}

List<String> redactEnv(
  List<String> env, {
  List<String> hostnames = const [],
  List<String> usernames = const [],
}) {
  return env.map((line) {
    final eq = line.indexOf('=');
    if (eq <= 0) {
      return redactText(line, hostnames: hostnames, usernames: usernames);
    }
    final key = line.substring(0, eq);
    final value = line.substring(eq + 1);
    final k = key.toLowerCase();
    if (k.contains('password') ||
        k.contains('token') ||
        k.contains('secret') ||
        k.contains('bearer') ||
        k.contains('api_key') ||
        k.endsWith('_key') ||
        k == 'key') {
      return '$key=<REDACTED>';
    }
    return '$key=${redactText(value, hostnames: hostnames, usernames: usernames)}';
  }).toList();
}

List<String> _sortedUnique(List<String> values) {
  final out = values.where((v) => v.trim().isNotEmpty).toSet().toList();
  out.sort((a, b) => b.length.compareTo(a.length));
  return out;
}

class _Indexer {
  _Indexer(this.prefix);

  final String prefix;
  final Map<String, String> _seen = {};
  int _n = 0;

  String _id(String raw) =>
      _seen.putIfAbsent(raw, () => '<${prefix}_${++_n}>');

  String replaceLiteral(String text, String value) {
    return text.replaceAllMapped(
      RegExp(r'\b' + RegExp.escape(value) + r'\b'),
      (m) => _id(m.group(0)!),
    );
  }

  String replaceRegex(String text, RegExp re) {
    return text.replaceAllMapped(re, (m) {
      final raw = m.group(0)!;
      if (raw.startsWith('<')) {
        return raw;
      }
      return _id(raw);
    });
  }
}
