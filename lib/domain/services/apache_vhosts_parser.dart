import '../facts/enums.dart';
import '../facts/host_facts.dart';
import 'web_lens.dart';

/// M52: parses `apachectl -S` / `httpd -S`. Pure and total: the output comes
/// from the host, so nothing here throws. Line-based, no backtracking regexes.
///
/// One [WebVhost] per `namevhost` line, plus one per single-vhost line
/// (`*:80  name (file:line)`). The `default server` line only marks the
/// default and creates nothing. `-S` has no ssl flag, so `tls` is port 443.
List<WebVhost> parseApacheVhosts(String dashS) {
  final out = <WebVhost>[];
  String? listen;
  String? name;
  var aliases = <String>[];
  String file = '';
  String vhListen = '';
  var port = '';

  void flush() {
    final n = name;
    if (n != null) {
      out.add(
        WebVhost(
          serverNames: [n, ...aliases],
          listen: vhListen.isEmpty ? const [] : [vhListen],
          tls: port == '443',
          sourceFile: file,
        ),
      );
    }
    name = null;
    aliases = <String>[];
  }

  for (final raw in dashS.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.trim().isEmpty) continue;
    final indented = line.startsWith(' ') || line.startsWith('\t');
    final words = line.trim().split(RegExp(r'[ \t]+'));
    if (indented) {
      if (words.length >= 5 &&
          words[0] == 'port' &&
          words[2] == 'namevhost' &&
          _isPort(words[1])) {
        flush();
        final loc = _loc(words.last);
        if (loc == null) continue;
        name = words[3];
        file = loc;
        port = words[1];
        vhListen = listen ?? '*:$port';
      } else if (words.length == 2 && words[0] == 'alias' && name != null) {
        aliases.add(words[1]);
      }
      continue;
    }
    flush();
    if (words.length >= 4 &&
        words[1] == 'is' &&
        words[2] == 'a' &&
        words[3] == 'NameVirtualHost') {
      listen = words[0];
    } else if (words.length == 3) {
      final loc = _loc(words[2]);
      final p = _portOf(words[0]);
      if (loc != null && p != null) {
        listen = null;
        name = words[1];
        file = loc;
        port = p;
        vhListen = words[0];
      }
    } else {
      listen = null;
    }
  }
  flush();
  return out;
}

bool _isPort(String s) =>
    s.isNotEmpty &&
    s.length <= 5 &&
    s.codeUnits.every((c) => c >= 48 && c <= 57);

String? _portOf(String addr) {
  final i = addr.lastIndexOf(':');
  if (i < 0) return null;
  final p = addr.substring(i + 1);
  return _isPort(p) ? p : null;
}

/// `(path:line)` -> `path:line`, else null.
String? _loc(String w) {
  if (w.length < 5 || !w.startsWith('(') || !w.endsWith(')')) return null;
  final inner = w.substring(1, w.length - 1);
  final i = inner.lastIndexOf(':');
  if (i <= 0 || !_isPort(inner.substring(i + 1))) return null;
  return inner;
}

bool _httpdFamily(HostFacts f) =>
    f.pkg == PackageManager.dnf ||
    f.pkg == PackageManager.yum ||
    f.pkg == PackageManager.zypper;

String apacheConfigDir(HostFacts f) =>
    _httpdFamily(f) ? '/etc/httpd' : '/etc/apache2';

({String error, String access}) apacheDefaultLogs(HostFacts f) =>
    _httpdFamily(f)
    ? (error: '/var/log/httpd/error_log', access: '/var/log/httpd/access_log')
    : (
        error: '/var/log/apache2/error.log',
        access: '/var/log/apache2/access.log',
      );
