import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/services/apache_vhosts_parser.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/web_lens.dart';
import 'package:kelola/domain/services/web_lens_parser.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/units/shell_quote.dart';

/// M52 §5a: one read-only exec behind the nginx / Apache lens.
///
/// The host is untrusted. [binaries] and [unit] came from its output, so each
/// is used only if it passes a whitelist, and then single-quoted. Cert and log
/// paths are taken from the config dump inside the remote shell and only ever
/// reach a command as a quoted variable (`"$p"`) after the same whitelist as
/// spec §7b. Only the certificate directive (`ssl_certificate` /
/// `SSLCertificateFile`, matched as the whole first token) feeds `openssl`;
/// private key paths never reach any command.
///
/// Privileged reads run plain first, then the same argv under `sudo -n`, so the
/// exact-argv lines in `/etc/sudoers.d/kelola-web` (§7b) match:
/// `<bin> -t`, `<nginx> -T` / `<ctl> -S`,
/// `<openssl> x509 -noout -enddate -subject -ext subjectAltName -in <path>`,
/// `<tail> -n 60 <error log>`, `<tail> -n 2000 <access log>`.
///
/// Host output is printed with a `|` prefix; see [parseWebLens].
class WebLensProbe extends Probe<WebLens> {
  const WebLensProbe({required this.id, required this.binaries, this.unit});

  /// [ServiceId.nginx] or [ServiceId.apache]; anything else reads as nginx.
  final ServiceId id;

  /// Binary name -> absolute path, as detected on the host.
  final Map<String, String> binaries;

  /// Detected unit (`nginx.service`) or OpenRC service (`nginx`).
  final String? unit;

  bool get _apache => id == ServiceId.apache;

  /// apachectl / apache2ctl set up the environment `apache2 -S` needs on
  /// Debian; httpd runs directly on the RHEL family.
  static const _apacheCtls = ['apachectl', 'apache2ctl', 'httpd'];

  static final _safeBin = RegExp(r'^/[A-Za-z0-9._/+-]+$');

  /// Max certificates probed per read.
  static const maxCerts = 50;

  @override
  String get auditTitle => _apache ? 'Read Apache' : 'Read nginx';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 30);

  /// The first detected binary whose path is safe and really names that
  /// binary; else the bare catalog name (a constant).
  String _bin(List<String> names) {
    for (final n in names) {
      final p = binaries[n];
      if (p != null &&
          p.length <= 4096 &&
          _safeBin.hasMatch(p) &&
          !p.contains('..') &&
          p.endsWith('/$n')) {
        return p;
      }
    }
    return names.first;
  }

  String? get _safeUnit {
    final u = unit;
    if (u == null || u.isEmpty || u.length > 256) return null;
    return isSudoersSafeUnitName(u) ? u : null;
  }

  List<String> _activeLines(HostFacts facts) {
    final u = _safeUnit;
    if (u == null) return const [];
    switch (facts.init) {
      case InitSystem.systemd:
        return [
          "systemctl is-active ${shellSingleQuote(u)} 2>/dev/null | sed 's/^/|/'",
        ];
      case InitSystem.openrc:
        return ["rc-service ${shellSingleQuote(u)} status 2>&1 | sed 's/^/|/'"];
      case InitSystem.sysvinit:
      case InitSystem.unknown:
        return const [];
    }
  }

  @override
  String command(HostFacts facts) {
    final bin = _bin(_apache ? _apacheCtls : const ['nginx']);
    final logs = _apache
        ? apacheDefaultLogs(facts)
        : (
            error: '/var/log/nginx/error.log',
            access: '/var/log/nginx/access.log',
          );
    return [
      'export LC_ALL=C',
      r'try() { "$@" 2>/dev/null || sudo -n "$@" 2>/dev/null; }',
      // Prints the value of directive $1 (whole first token, any case),
      // without `;` or surrounding quotes, only if it is a safe absolute path;
      // unique, at most $2.
      'pick() {',
      r'''  awk -v k="$1" -v m="$2" -v q="'" 'tolower($1) == k {''',
      r'''    v = $2; sub(/;$/, "", v); f = substr(v, 1, 1)''',
      r'''    if ((f == "\"" || f == q) && length(v) > 1 && substr(v, length(v), 1) == f) v = substr(v, 2, length(v) - 2)''',
      r'''    if (v ~ "^/[-A-Za-z0-9._/+@]+$" && index(v, "..") == 0 && !(v in s)) { s[v] = 1; print v; if (++c >= m + 0) exit }''',
      "  }'",
      '}',
      // Host output gets a `|` prefix so it can never look like a marker.
      r'''out() { [ -z "$1" ] || printf '%s\n' "$1" | sed 's/^/|/'; }''',
      'B=${shellSingleQuote(bin)}',
      r'O=$(command -v openssl 2>/dev/null); case "$O" in /*) ;; *) O=openssl ;; esac',
      r'T=$(command -v tail 2>/dev/null); case "$T" in /*) ;; *) T=tail ;; esac',
      'echo ---TOOLS---',
      r'''case "$O" in /*) printf '|openssl %s\n' "$O" ;; esac''',
      r'''case "$T" in /*) printf '|tail %s\n' "$T" ;; esac''',
      'echo ---ACTIVE---',
      ..._activeLines(facts),
      'echo ---CONFTEST---',
      // Plain first; on failure the same argv under sudo -n, whose output and
      // rc are reported. sudo refusing (not a config error) prints nosudo.
      r'if o=$("$B" -t 2>&1); then r=0; else',
      r'  o=$(sudo -n "$B" -t 2>&1); r=$?',
      r'''  if [ "$r" != 0 ] && { ! command -v sudo >/dev/null 2>&1 || printf '%s\n' "$o" | grep -qiE 'sudo.*(password|interactive authentication|no tty|askpass|a terminal is required|not allowed to execute|not in the sudoers)'; }; then r=nosudo; o=; fi''',
      'fi',
      r'out "$o"',
      r'echo "@rc=$r"',
      'echo ---DUMP---',
      if (_apache)
        r'd=$(try "$B" -S </dev/null)'
      else
        r'd=$(try "$B" -T </dev/null)',
      r'out "$d"',
      'echo ---CERTS---',
      if (_apache)
        'grep -rhsi SSLCertificateFile ${shellSingleQuote(apacheConfigDir(facts))} '
            '| pick sslcertificatefile $maxCerts |'
      else
        'printf \'%s\\n\' "\$d" | pick ssl_certificate $maxCerts |',
      r'while IFS= read -r p; do',
      r'  echo "@cert=$p"',
      r'  if o=$(try "$O" x509 -noout -enddate -subject -ext subjectAltName -in "$p" </dev/null); then',
      r'    echo @read=ok; out "$o"',
      r'  else echo @read=fail; fi',
      'done',
      'echo @done=1',
      'echo ---ERRLOG---',
      if (_apache)
        r'''e=$(printf '%s\n' "$d" | awk '$1 == "Main" && $2 == "ErrorLog:" { print "errorlog", $3 }' | pick errorlog 1)'''
      else
        r'''e=$(printf '%s\n' "$d" | pick error_log 1)''',
      '[ -n "\$e" ] || e=${shellSingleQuote(logs.error)}',
      r'echo "@path=$e"',
      r'if o=$(try "$T" -n 60 "$e" </dev/null); then echo @read=ok; out "$o"; else echo @read=fail; fi',
      'echo ---ACCESS---',
      if (_apache)
        'a=${shellSingleQuote(logs.access)}'
      else ...[
        r'''a=$(printf '%s\n' "$d" | pick access_log 1)''',
        '[ -n "\$a" ] || a=${shellSingleQuote(logs.access)}',
      ],
      r'echo "@path=$a"',
      r'if o=$(try "$T" -n 2000 "$a" </dev/null); then echo @read=ok;',
      r'''  [ -z "$o" ] || out "$(printf '%s\n' "$o" | awk '{print $9}' | sort | uniq -c)"''',
      r'else echo @read=fail; fi',
      'true',
    ].join('\n');
  }

  @override
  WebLens parse(String stdout, String stderr, int exitCode) =>
      parseWebLens(stdout, id: id, now: DateTime.now());
}
