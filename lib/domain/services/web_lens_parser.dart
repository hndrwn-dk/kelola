import '../exceptions.dart';
import '../sudo_hint.dart';
import 'apache_vhosts_parser.dart';
import 'nginx_dump_parser.dart';
import 'service_catalog.dart';
import 'web_lens.dart';

/// M52 §5a: parses [WebLensProbe] output. Pure and total: everything here was
/// printed by the host. The only throw is [SudoRequiredException] when the
/// config dump needs sudo and `sudo -n` is not granted.
///
/// Output format (written by the probe script, not the host):
/// - `---NAME---` section markers, unprefixed;
/// - `@key=value` lines, unprefixed, with values the script validated;
/// - `|text` host output, one line each. The prefix means host text can never
///   look like a marker or a meta line.

const _markers = {
  '---TOOLS---': _Sec.tools,
  '---ACTIVE---': _Sec.active,
  '---CONFTEST---': _Sec.conftest,
  '---DUMP---': _Sec.dump,
  '---CERTS---': _Sec.certs,
  '---ERRLOG---': _Sec.errlog,
  '---ACCESS---': _Sec.access,
};

enum _Sec { tools, active, conftest, dump, certs, errlog, access }

/// [WebLens.sectionErrors] for the config test when `sudo -n` was refused.
const webConfigTestNoSudo =
    'Config test needs sudo -n; not granted for this lens';

/// Matches the shell-side whitelist for cert and log paths (spec §7b).
final _safePath = RegExp(r'^/[A-Za-z0-9._/+@-]+$');

/// Binary paths (`command -v`).
final _safeToolPath = RegExp(r'^/[A-Za-z0-9._/+-]+$');

bool isSafeWebPath(String p) =>
    p.length <= 4096 && _safePath.hasMatch(p) && !p.contains('..');

/// Owner / group / login group names from `stat` and `id -nG`.
final _safeName = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');
final _safeMode = RegExp(r'^[0-7]{3,4}$');

const _maxLines = 60;
const _maxConfigErrors = 50;
const _maxLineLength = 2000;

class _Section {
  final data = <String>[];
  final meta = <MapEntry<String, String>>[];

  /// Meta and data in order (needed for per-cert attribution).
  final items = <({String? key, String value})>[];

  String? metaValue(String key) {
    for (final m in meta) {
      if (m.key == key) return m.value;
    }
    return null;
  }
}

WebLens parseWebLens(
  String stdout, {
  required ServiceId id,
  required DateTime now,
}) {
  final sections = <_Sec, _Section>{};
  _Section? cur;
  for (final raw in stdout.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.startsWith('|')) {
      final text = line.substring(1);
      cur?.data.add(text);
      cur?.items.add((key: null, value: text));
      continue;
    }
    final sec = _markers[line];
    if (sec != null) {
      // First occurrence wins; a repeat would only come from a broken script.
      cur = sections.containsKey(sec) ? null : (sections[sec] = _Section());
      continue;
    }
    if (line.startsWith('@')) {
      final eq = line.indexOf('=');
      if (eq > 1 && cur != null) {
        final key = line.substring(1, eq);
        final value = line.substring(eq + 1);
        cur.meta.add(MapEntry(key, value));
        cur.items.add((key: key, value: value));
      }
    }
    // Anything else is junk (stderr noise, a cut line): ignored.
  }

  final errors = <WebLensSection, String>{};
  final service = id == ServiceId.apache ? 'apache' : 'nginx';
  final label = descriptorFor(id).label;

  // TOOLS
  final toolPaths = <String, String>{};
  for (final l in sections[_Sec.tools]?.data ?? const <String>[]) {
    final parts = l.trim().split(' ');
    if (parts.length != 2) continue;
    if ((parts[0] == 'openssl' || parts[0] == 'tail') &&
        parts[1].length <= 4096 &&
        _safeToolPath.hasMatch(parts[1]) &&
        !parts[1].contains('..')) {
      toolPaths[parts[0]] = parts[1];
    }
  }

  final loginGroups = _groups(sections[_Sec.tools]?.metaValue('groups'));

  // ACTIVE
  final activeState = _activeState(sections[_Sec.active]?.data);
  if (activeState == null) {
    errors[WebLensSection.active] = 'Could not read the $label service state';
  }

  // CONFTEST
  bool? configOk;
  var configErrors = const <String>[];
  var noSudo = false;
  final ct = sections[_Sec.conftest];
  final rc = ct?.metaValue('rc');
  if (rc == '0') {
    configOk = true;
  } else if (rc == 'nosudo') {
    noSudo = true;
    errors[WebLensSection.configTest] = webConfigTestNoSudo;
  } else if (rc != null && _isInt(rc)) {
    configOk = false;
    configErrors = [
      for (final l in ct!.data)
        if (l.trim().isNotEmpty) _clip(l),
    ].take(_maxConfigErrors).toList();
  } else {
    errors[WebLensSection.configTest] = 'Could not run the config test';
  }

  // DUMP
  var vhosts = const <WebVhost>[];
  var configFiles = const <String>[];
  final dumpLines = sections[_Sec.dump]?.data ?? const <String>[];
  final dumpText = dumpLines.join('\n');
  if (dumpText.trim().isEmpty) {
    if (noSudo) {
      throw SudoRequiredException(
        SudoHintContext.webServices(service: service),
      );
    }
    errors[WebLensSection.dump] = configOk == false
        ? 'Config test failed; no config dump'
        : 'Could not read the config dump';
  } else if (id == ServiceId.apache) {
    vhosts = parseApacheVhosts(dumpText);
    configFiles = _apacheConfigFiles(vhosts);
  } else {
    final r = parseNginxDump(dumpText);
    vhosts = r.vhosts;
    configFiles = r.sourceFiles;
    if (r.truncated) {
      errors[WebLensSection.dump] =
          'Config dump truncated; showing complete vhosts only';
    }
  }

  // CERTS
  final certs = <String, WebCert>{};
  final certSec = sections[_Sec.certs];
  if (certSec == null || certSec.metaValue('done') == null) {
    // Missing, or cut before the loop finished.
    errors[WebLensSection.certs] = 'Could not read certificates';
  }
  certs.addAll(_certs(certSec));
  if (certSec != null) {
    final unreadable = certs.values.where((c) => c.notAfter == null).length;
    if (unreadable > 0) {
      errors[WebLensSection.certs] =
          'Could not read $unreadable of ${certs.length} certificates';
    }
    // Apache: no enabled config file could be read, so the certificate
    // list is unknown, not empty.
    if (certSec.metaValue('src') == 'none') {
      errors[WebLensSection.certs] =
          'Could not read the $label config for certificates';
    }
  }

  // Apache (fix 3): tie each cert to its -S vhost, or the server config.
  var vhostCertsUnlinked = false;
  if (id == ServiceId.apache) {
    final linked = _linkApacheCerts(
      vhosts,
      certSec,
      anyCert: certs.isNotEmpty,
    );
    vhosts = linked.vhosts;
    vhostCertsUnlinked = linked.unlinked;
  }

  // ERRLOG
  final el = _log(sections[_Sec.errlog]);
  final errorLogTail = el.ok
      ? [
          for (final l in el.lines)
            if (l.isNotEmpty) _clip(l),
        ]
      : const <String>[];
  final errorLogTailCapped = errorLogTail.length > _maxLines
      ? errorLogTail.sublist(errorLogTail.length - _maxLines)
      : errorLogTail;
  if (!el.ok) {
    errors[WebLensSection.errorLog] =
        'Could not read error log: no access with or without sudo -n';
  }

  // ACCESS
  final ac = _log(sections[_Sec.access]);
  final statusCounts = <int, int>{};
  if (ac.ok) {
    for (final l in ac.lines) {
      final b = _bucket(l);
      if (b == null) continue;
      statusCounts[b.$1] = (statusCounts[b.$1] ?? 0) + b.$2;
    }
  } else {
    errors[WebLensSection.access] =
        'Could not read access log: no access with or without sudo -n';
  }

  return WebLens(
    id: id,
    readAt: now,
    activeState: activeState,
    configOk: configOk,
    configErrors: configErrors,
    vhosts: vhosts,
    certsByPath: certs,
    errorLogTail: errorLogTailCapped,
    statusCounts: statusCounts,
    sectionErrors: errors,
    toolPaths: toolPaths,
    errorLogPath: el.path,
    accessLogPath: ac.path,
    configFiles: configFiles,
    errorLogStat: _stat(sections[_Sec.errlog]?.metaValue('stat')),
    accessLogStat: _stat(sections[_Sec.access]?.metaValue('stat')),
    loginGroups: loginGroups,
    vhostCertsUnlinked: vhostCertsUnlinked,
  );
}

/// Max `@certin` lines read. The probe prints at most one more, so reaching
/// that one means links were cut.
const webMaxCertLinks = 1000;

/// Max certs linked to one vhost.
const _maxCertsPerVhost = 256;

/// Fix 3. The probe prints `@certin=<scope> <cert path>` per
/// `SSLCertificateFile`, in read order: `global` (outside any
/// `<VirtualHost>`), `<file>:<line>` (the `<VirtualHost` line, as `-S` prints
/// it) or `vhost` (in a file whose path it would not print). A vhost gets the
/// certs of its own `file:line`; a TLS vhost with none inherits the last
/// global one, unless `unlinked`: a cert could not be tied to a vhost, so
/// any vhost may be the one that owns it and no inheritance is guessed.
/// Links that did match stay.
({List<WebVhost> vhosts, bool unlinked}) _linkApacheCerts(
  List<WebVhost> vhosts,
  _Section? sec, {
  required bool anyCert,
}) {
  final own = <String, List<String>>{};
  String? global;
  var count = 0;
  var unlinked = false;
  for (final m in sec?.meta ?? const <MapEntry<String, String>>[]) {
    if (m.key != 'certin') continue;
    if (++count > webMaxCertLinks) {
      // Past the cap (the probe prints one more): the rest is unknown.
      unlinked = true;
      break;
    }
    final parts = m.value.split(' ');
    if (parts.length != 2 || !isSafeWebPath(parts[1])) continue;
    final scope = parts[0];
    final path = parts[1];
    if (scope == 'global') {
      global = path;
    } else if (scope == 'vhost') {
      unlinked = true;
    } else if (_isVhostLoc(scope)) {
      final list = own[scope] ??= <String>[];
      if (!list.contains(path) && list.length < _maxCertsPerVhost) {
        list.add(path);
      }
    }
  }
  // Certs read but no link printed: attribution unknown.
  if (count == 0 && anyCert) unlinked = true;
  final locs = {for (final v in vhosts) v.sourceFile};
  if (own.keys.any((k) => !locs.contains(k))) unlinked = true;
  final inherited = unlinked ? null : global;
  return (
    vhosts: [
      for (final v in vhosts)
        if (own[v.sourceFile] case final paths?)
          _withCerts(v, paths, inherited: false)
        else if (v.tls && inherited != null)
          _withCerts(v, [inherited], inherited: true)
        else
          v,
    ],
    unlinked: unlinked,
  );
}

/// `<safe absolute path>:<line>`.
bool _isVhostLoc(String s) {
  final i = s.lastIndexOf(':');
  if (i <= 0) return false;
  final line = s.substring(i + 1);
  return line.isNotEmpty &&
      line.length <= 9 &&
      line.codeUnits.every((c) => c >= 48 && c <= 57) &&
      isSafeWebPath(s.substring(0, i));
}

WebVhost _withCerts(
  WebVhost v,
  List<String> paths, {
  required bool inherited,
}) => WebVhost(
  serverNames: v.serverNames,
  listen: v.listen,
  tls: v.tls,
  root: v.root,
  certPath: paths.first,
  certPaths: List.unmodifiable(paths),
  sourceFile: v.sourceFile,
  inherited: inherited,
);

/// `@stat=<owner> <group> <mode>`; null unless all three are valid.
WebLogStat? _stat(String? v) {
  if (v == null) return null;
  final p = v.split(' ');
  if (p.length != 3) return null;
  if (!_safeName.hasMatch(p[0]) ||
      !_safeName.hasMatch(p[1]) ||
      !_safeMode.hasMatch(p[2])) {
    return null;
  }
  return WebLogStat(owner: p[0], group: p[1], mode: p[2]);
}

/// `@groups=<names>`: valid names only; null (unknown) when none is valid.
List<String>? _groups(String? v) {
  if (v == null) return null;
  final names = [
    for (final g in v.split(' '))
      if (_safeName.hasMatch(g)) g,
  ];
  return names.isEmpty ? null : List.unmodifiable(names);
}

/// The files `-S` names for vhosts (`path:line`, line dropped), once each.
List<String> _apacheConfigFiles(List<WebVhost> vhosts) {
  final out = <String>{};
  for (final v in vhosts) {
    final i = v.sourceFile.lastIndexOf(':');
    if (i <= 0) continue;
    out.add(v.sourceFile.substring(0, i));
  }
  return List.unmodifiable(out);
}

/// `@cert=<path>`, `@read=ok|fail`, then openssl's lines for that path.
Map<String, WebCert> _certs(_Section? sec) {
  final certs = <String, WebCert>{};
  String? path;
  var ok = false;
  var lines = <String>[];
  void flush() {
    final p = path;
    if (p != null && !certs.containsKey(p)) {
      certs[p] = ok ? _parseCert(p, lines) : WebCert(path: p);
    }
    path = null;
    ok = false;
    lines = <String>[];
  }

  for (final it in sec?.items ?? const <({String? key, String value})>[]) {
    if (it.key == 'cert') {
      flush();
      path = isSafeWebPath(it.value) ? it.value : null;
    } else if (it.key == 'read') {
      ok = it.value == 'ok';
    } else if (it.key == null && path != null) {
      lines.add(it.value);
    }
  }
  flush();
  return certs;
}

bool _isInt(String s) =>
    s.isNotEmpty &&
    s.length <= 4 &&
    s.codeUnits.every((c) => c >= 48 && c <= 57);

String _clip(String s) =>
    s.length > _maxLineLength ? s.substring(0, _maxLineLength) : s;

/// `active` (systemctl is-active) or ` * status: started` (OpenRC).
String? _activeState(List<String>? lines) {
  if (lines == null) return null;
  for (final raw in lines) {
    final l = raw.trim();
    final i = l.indexOf('status:');
    final v = i >= 0 ? l.substring(i + 7).trim() : l;
    if (_knownStates.contains(v)) return v;
  }
  return null;
}

/// systemd ActiveState values and OpenRC status words. Anything else is junk.
const _knownStates = {
  'active', 'reloading', 'refreshing', 'inactive', 'failed', 'activating',
  'deactivating', 'maintenance', //
  'started', 'stopped', 'crashed', 'starting', 'stopping', 'hotplugged',
};

({bool ok, String? path, List<String> lines}) _log(_Section? s) {
  if (s == null) return (ok: false, path: null, lines: const []);
  final p = s.metaValue('path');
  return (
    ok: s.metaValue('read') == 'ok',
    path: p != null && isSafeWebPath(p) ? p : null,
    lines: s.data,
  );
}

/// One `uniq -c` line: `     30 200` -> (200, 30). Statuses outside
/// 100..599, `-` and junk are skipped.
(int, int)? _bucket(String line) {
  final parts = line.trim().split(RegExp(r'[ \t]+'));
  if (parts.length != 2) return null;
  final count = _smallInt(parts[0], 9);
  final status = _smallInt(parts[1], 3);
  if (count == null || status == null || status < 100 || status > 599) {
    return null;
  }
  return (status, count);
}

int? _smallInt(String s, int maxDigits) {
  if (s.isEmpty || s.length > maxDigits) return null;
  if (!s.codeUnits.every((c) => c >= 48 && c <= 57)) return null;
  return int.parse(s);
}

const _months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6, //
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

WebCert _parseCert(String path, List<String> lines) {
  DateTime? notAfter;
  String? cn;
  final sans = <String>[];
  var inSan = false;
  for (final raw in lines) {
    final l = raw.trim();
    if (l.startsWith('notAfter=')) {
      notAfter ??= _parseOpensslDate(l.substring(9));
      inSan = false;
    } else if (l.startsWith('subject=')) {
      cn ??= _subjectCn(l.substring(8));
      inSan = false;
    } else if (l.startsWith('X509v3 Subject Alternative Name')) {
      inSan = true;
    } else if (inSan && l.isNotEmpty) {
      for (final e in l.split(',')) {
        final t = e.trim();
        if (t.startsWith('DNS:') && t.length > 4 && sans.length < 100) {
          sans.add(t.substring(4));
        }
      }
      inSan = false;
    }
  }
  return WebCert(
    path: path,
    notAfter: notAfter,
    subjectCn: cn,
    sans: List.unmodifiable(sans),
  );
}

/// `Nov 15 01:32:00 2026 GMT` (day may be space-padded).
DateTime? _parseOpensslDate(String s) {
  final p = s.trim().split(RegExp(r' +'));
  if (p.length != 5 || p[4] != 'GMT') return null;
  final month = _months[p[0]];
  final day = _smallInt(p[1], 2);
  final year = _smallInt(p[3], 4);
  final hms = p[2].split(':');
  if (month == null || day == null || year == null || hms.length != 3) {
    return null;
  }
  final h = _smallInt(hms[0], 2);
  final m = _smallInt(hms[1], 2);
  final sec = _smallInt(hms[2], 2);
  if (h == null || m == null || sec == null) return null;
  if (day < 1 || day > 31 || h > 23 || m > 59 || sec > 60) return null;
  return DateTime.utc(year, month, day, h, m, sec);
}

/// `CN = soon.lab, O = "Acme, Inc"` (OpenSSL 1.1+) or `/C=US/CN=soon.lab`
/// (older). Quoted values may contain commas.
String? _subjectCn(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final parts = <String>[];
  if (t.startsWith('/')) {
    parts.addAll(t.substring(1).split('/'));
  } else {
    final buf = StringBuffer();
    var quoted = false;
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (c == '\\' && i + 1 < t.length) {
        buf.write(t[++i]);
      } else if (c == '"') {
        quoted = !quoted;
      } else if (c == ',' && !quoted) {
        parts.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    parts.add(buf.toString());
  }
  for (final part in parts) {
    final eq = part.indexOf('=');
    if (eq < 0) continue;
    if (part.substring(0, eq).trim() == 'CN') {
      final v = part.substring(eq + 1).trim();
      return v.isEmpty ? null : v;
    }
  }
  return null;
}
