import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/sudo/unit_sudoers_grant.dart';

/// M52 §7b: exact read rules for the web lenses. Written only from a lens,
/// never by Enable Kelola sudo, so it never reads as outdated rules there.
const kelolaWebSudoersPath = '/etc/sudoers.d/kelola-web';

const webGrantOkMarker = 'KELOLA_WEB_GRANT_OK';

/// Printed (with the binary's path, base64) when a binary failed the
/// host-side ownership check; nothing is written then.
const webGrantUntrustedMarker = 'KELOLA_WEB_GRANT_UNTRUSTED';

/// Printed (with the path, base64) for each cert or log path whose
/// directory chain failed the host-side check. Only the lines naming that
/// path are left out; the rest are installed.
const webGrantSkippedMarker = 'KELOLA_WEB_GRANT_SKIPPED';

/// Printed (with the failing path, base64, and a [WebConfigRefusalReason]
/// name) when the server config is not root-controlled. Only the config test
/// lines (`-t`, and `-T` or `-S`) are left out; the rest are installed.
const webGrantConfigMarker = 'KELOLA_WEB_GRANT_CONFIG';

/// Exit status of the grant script when every line was skipped, so nothing
/// was read or written.
const webGrantNothingExit = 6;

/// Most entries (files, directories, links, dump-named files) the config
/// check looks at, across every tree; reaching it counts as untrusted.
const webConfigTrustMaxEntries = 2000;

/// Config roots, module directories and Apache's `envvars` (sourced by
/// `apachectl` as root), checked with their whole trees. nginx's root is the
/// directory of `--conf-path` from `nginx -V`, else this one.
const webNginxDefaultConfigRoot = '/etc/nginx';
const webNginxModuleDirs = ['/usr/lib/nginx/modules', '/usr/lib64/nginx/modules'];

/// Every match of `/usr/share/nginx/modules*` is checked as well.
const webNginxShareModulesGlob = '/usr/share/nginx/modules';
const webApacheConfigRoots = ['/etc/apache2', '/etc/httpd'];
const webApacheEnvvars = '/etc/apache2/envvars';
const webApacheModuleDirs = ['/usr/lib/apache2/modules', '/usr/lib64/httpd/modules'];

/// Why the config test was not granted ([webGrantConfigMarker]).
enum WebConfigRefusalReason { owner, mode, cap, loop, missing, unreadable }

/// The first config path that failed the host-side check, and why.
class WebGrantConfigRefusal {
  const WebGrantConfigRefusal({required this.path, required this.reason});

  /// A plain absolute path, or `a config file` when the host's text was not
  /// one.
  final String path;
  final WebConfigRefusalReason reason;
}

/// System directories. A NOPASSWD rule on a binary the login user can
/// replace would be a root shell, and binary paths come from the host's own
/// output, so only these directories are ever granted (not `/usr/local`,
/// which is often group-writable). The grant script also checks on the host
/// that every hop to each binary (each directory, each symlink, the final
/// file) is root-owned and not group- or other-writable
/// ([webBinaryTrustShell]).
const webGrantSystemDirs = {'/usr/bin', '/usr/sbin', '/bin', '/sbin'};

final _userName = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_.-]*$');

/// Spec §7b. Leaves out every sudoers special character (space, `,`, `:`,
/// `=`, `\`, `*`, `?`, `[`, `]`, `!`, `#`) and every shell one.
final _grantPath = RegExp(r'^/[A-Za-z0-9._/+@-]+$');

/// Whether [path] is exactly `<system dir>/<name>`.
bool isGrantableWebBinary(String? path, String name) {
  if (path == null) return false;
  final i = path.lastIndexOf('/');
  if (i <= 0) return false;
  return webGrantSystemDirs.contains(path.substring(0, i)) &&
      path.substring(i + 1) == name;
}

/// Whether a host-reported cert or log [path] may be an argument in a rule.
bool isGrantableWebPath(String path) =>
    path.length <= 4096 &&
    _grantPath.hasMatch(path) &&
    !path.contains('..') &&
    !path.contains('//');

/// The full sudoers lines (`<user> ALL=(root) NOPASSWD: <bin> <args>`) for
/// the reads [WebLensProbe] and the config test in `ConfigTestedReloadProbe`
/// run under `sudo -n`, byte for byte:
///
/// - `<bin> -t`, and `<nginx> -T` or `<ctl> -S`;
/// - `<openssl> x509 -noout -enddate -subject -ext subjectAltName -in <cert>`,
///   one per cert;
/// - `<tail> -n 60 <error log>`, `<tail> -n 2000 <access log>`.
///
/// [binaries] and [toolPaths] are as detected on the host. The server binary
/// is the one the probes pick ([safeWebBinary]); a binary or tool gets lines
/// only if it sits in [webGrantSystemDirs] under its own name. A path gets a
/// line only if [isGrantableWebPath]. [certPaths] must be certificate paths
/// (`WebLens.certsByPath` keys), never key paths. Empty when [user] could
/// change the rule, or [id] is not nginx or Apache.
List<String> webGrantLines({
  required String user,
  required ServiceId id,
  required Map<String, String> binaries,
  Map<String, String> toolPaths = const {},
  List<String> certPaths = const [],
  String? errorLog,
  String? accessLog,
}) => [
  for (final e in _webGrantEntries(
    user: user,
    id: id,
    binaries: binaries,
    toolPaths: toolPaths,
    certPaths: certPaths,
    errorLog: errorLog,
    accessLog: accessLog,
  ))
    e.line,
];

/// [webGrantLines], each with the cert or log path it names (null for the
/// server binary's own lines).
List<({String line, String? path})> _webGrantEntries({
  required String user,
  required ServiceId id,
  required Map<String, String> binaries,
  required Map<String, String> toolPaths,
  required List<String> certPaths,
  required String? errorLog,
  required String? accessLog,
}) {
  // `ALL` in the user field would be every user.
  if (!_userName.hasMatch(user) || user.toUpperCase() == 'ALL') {
    return const [];
  }
  if (id != ServiceId.nginx && id != ServiceId.apache) return const [];
  final commands = <({String cmd, String? path})>[];

  final names = webConfigTestBinaryNames(id);
  final bin = safeWebBinary(binaries, names);
  if (bin != null && names.any((n) => isGrantableWebBinary(bin, n))) {
    commands
      ..add((cmd: '$bin -t', path: null))
      ..add((cmd: id == ServiceId.apache ? '$bin -S' : '$bin -T', path: null));
  }

  final openssl = toolPaths['openssl'];
  if (isGrantableWebBinary(openssl, 'openssl')) {
    for (final p in certPaths) {
      if (!isGrantableWebPath(p)) continue;
      commands.add((
        cmd:
            '$openssl x509 -noout -enddate -subject -ext subjectAltName '
            '-in $p',
        path: p,
      ));
    }
  }

  final tail = toolPaths['tail'];
  if (isGrantableWebBinary(tail, 'tail')) {
    if (errorLog != null && isGrantableWebPath(errorLog)) {
      commands.add((cmd: '$tail -n 60 $errorLog', path: errorLog));
    }
    if (accessLog != null && isGrantableWebPath(accessLog)) {
      commands.add((cmd: '$tail -n 2000 $accessLog', path: accessLog));
    }
  }

  final seen = <String>{};
  return [
    for (final c in commands)
      if (seen.add(c.cmd))
        (line: '$user ALL=(root) NOPASSWD: ${c.cmd}', path: c.path),
  ];
}

/// Lens read rules for one web server, shown to the user before they are
/// written to [kelolaWebSudoersPath].
class WebSudoersGrant {
  const WebSudoersGrant._({
    required this.id,
    required this.user,
    required this.lines,
    required this.linePaths,
    required this.configFiles,
  });

  final ServiceId id;
  final String user;
  final List<String> lines;

  /// For each of [lines], the cert or log path it names, or null (the
  /// server binary's config test lines). The grant script checks each path
  /// on the host and leaves out the lines of a path that fails; the config
  /// test lines are left out unless the server config is root-controlled.
  final List<String?> linePaths;

  /// Config files the lens's dump named (`WebLens.configFiles`), each
  /// checked on the host before a config test line is installed. Empty
  /// without a config test line.
  final List<String> configFiles;

  /// Null when [webGrantLines] gives no line. [configFiles] is as the host
  /// reported it; the grant script refuses the config test when one of them
  /// cannot be checked.
  static WebSudoersGrant? tryCreate({
    required String user,
    required ServiceId id,
    required Map<String, String> binaries,
    Map<String, String> toolPaths = const {},
    List<String> certPaths = const [],
    String? errorLog,
    String? accessLog,
    List<String> configFiles = const [],
  }) {
    final entries = _webGrantEntries(
      user: user,
      id: id,
      binaries: binaries,
      toolPaths: toolPaths,
      certPaths: certPaths,
      errorLog: errorLog,
      accessLog: accessLog,
    );
    if (entries.isEmpty) return null;
    final configTest = entries.any((e) => e.path == null);
    return WebSudoersGrant._(
      id: id,
      user: user,
      lines: List.unmodifiable([for (final e in entries) e.line]),
      linePaths: List.unmodifiable([for (final e in entries) e.path]),
      configFiles: configTest
          ? List.unmodifiable(configFiles.toSet().toList())
          : const [],
    );
  }

  /// The server binary of the config test lines, or null without them.
  String? get configTestBinary {
    for (var i = 0; i < lines.length; i++) {
      if (linePaths[i] == null) return _binaryOf(lines[i]);
    }
    return null;
  }

  static String _binaryOf(String line) {
    const sep = ' NOPASSWD: ';
    final cmd = line.substring(line.indexOf(sep) + sep.length);
    return cmd.substring(0, cmd.indexOf(' '));
  }

  /// Each distinct binary the lines name, in order.
  List<String> get binaries {
    final out = <String>[];
    for (final l in lines) {
      final bin = _binaryOf(l);
      if (!out.contains(bin)) out.add(bin);
    }
    return out;
  }

  String get linesHash =>
      sha256.convert(utf8.encode(lines.join('\n'))).toString();
}

/// Remote sh that reads the sudo password on stdin (one line) and adds the
/// grant's lines to [kelolaWebSudoersPath], keeping the lines already there.
/// Same script as the per-unit grant ([buildSudoersGrantScript]), with the
/// host-side checks ([webBinaryTrustShell]) first: every binary must pass or
/// nothing is written; a cert or log path that fails only drops the lines
/// naming it ([webGrantSkippedMarker]). When every line is dropped, the
/// script exits [webGrantNothingExit] before any sudo call.
///
/// The config test lines (`-t`, `-T` / `-S`) run the server as root, and it
/// loads the modules its config names, so they are gated too
/// ([_configTrustShell]): when the config is not root-controlled only they
/// are left out ([webGrantConfigMarker]).
///
/// [trustOwners] and [configPrefix] exist for tests only (see
/// [webBinaryTrustShell]; [configPrefix] is put in front of every fixed
/// config root, module directory and `envvars` location).
String buildWebGrantScript(
  WebSudoersGrant g, {
  @visibleForTesting List<String> trustOwners = const ['root'],
  @visibleForTesting String configPrefix = '',
}) {
  final paths = _distinctPaths(g.linePaths);
  const cfg = '[ "\$KELOLA_CFG" = 1 ]';
  String gate(String? p) =>
      p == null ? cfg : '[ "\$KELOLA_P${paths.indexOf(p)}" = 1 ]';
  final gates = [for (final p in g.linePaths) gate(p)];
  final bin = g.configTestBinary;
  final stop =
      '${[
        for (final (j, _) in paths.indexed) '[ "\$KELOLA_P$j" = 1 ]',
        if (bin != null) cfg,
      ].join(' || ')}'
      ' || exit $webGrantNothingExit\n';
  final config = bin == null
      ? ''
      : _configTrustShell(
          g.id,
          bin,
          g.configFiles,
          trustOwners,
          prefix: configPrefix,
        );
  return buildSudoersGrantScript(
    path: kelolaWebSudoersPath,
    header: '# Kelola: lens read rules, one command per line. Safe to edit.',
    lines: g.lines,
    okMarker: webGrantOkMarker,
    preamble: _trustShell(g.binaries, paths, trustOwners) + config + stop,
    lineConditions: gates,
  );
}

/// Shell (run after [_trustShell], as the login user, no sudo) that sets
/// `KELOLA_CFG=1` only when everything the config test as root would load
/// is root-controlled; otherwise it prints [webGrantConfigMarker] with the
/// first failing path and reason, and `KELOLA_CFG` stays 0.
///
/// Checked, each through `kelola_walk` (`/` and every hop to it) and then as
/// a tree:
/// - nginx: the directory of `--conf-path` from `<bin> -V` (the binary has
///   passed its own check), else [webNginxDefaultConfigRoot]; Apache: each
///   of [webApacheConfigRoots] that exists (at least one must), plus
///   [webApacheEnvvars];
/// - module directories ([webNginxModuleDirs], every
///   `/usr/share/nginx/modules*`, [webApacheModuleDirs]) that exist; one
///   missing behind a clean chain is skipped, since only root could create
///   it;
/// - [configFiles] (from the dump), each walked as a file: one that is not a
///   plain path ([isGrantableWebPath]) cannot be checked, so it fails.
///
/// The tree rule: every file and directory owned by root and not group- or
/// other-writable; every symlink owned by root, its target walked hop by
/// hop, and a target directory scanned as its own tree (once; a link to a
/// directory above it is a loop). A directory the login cannot search is
/// not descended (nothing below it is reachable for the login), but it must
/// pass the rule itself; any other `find` error fails. A name with a
/// newline fails. At most [webConfigTrustMaxEntries] entries in all, and
/// `find` is cut off there, so a huge tree stays fast.
///
/// Fail-closed: `set -e` does not apply inside `kelola_cfg` (it runs as an
/// `if` condition), so every step checks its own status.
String _configTrustShell(
  ServiceId id,
  String bin,
  List<String> configFiles,
  List<String> owners, {
  required String prefix,
}) {
  if (prefix.isNotEmpty && !isGrantableWebPath(prefix)) {
    throw ArgumentError.value(prefix, 'prefix');
  }
  String b64(String s) => base64Encode(utf8.encode(s));
  String decoded(String s) => "\"\$(printf '%s' '${b64(s)}' | base64 -d)\"";
  final own = owners.map((o) => "-user '$o'").join(' -o ');
  // Always true; prunes a directory the login cannot search. If `test`
  // itself fails, nothing is pruned and find's own error fails the check.
  const pr = r'\( ! -type d -o ! -exec test ! -x {} \; -o -prune \)';
  final b = StringBuffer()
    ..writeln(
      prefix.isEmpty
          ? 'kelola_pre='
          : "kelola_pre=\$(printf '%s' '${b64(prefix)}' | base64 -d)",
    )
    ..writeln('kelola_cap=$webConfigTrustMaxEntries')
    // $1: a resolved, symlink-free directory that passed kelola_walk.
    ..writeln('kelola_tree() {')
    ..writeln(r'  kelola_left=$((kelola_cap - kelola_n))')
    ..writeln(
      '  kelola_list=\$({ find "\$1" $pr -print 2>/dev/null || echo x; } '
      r'| head -n "$((kelola_left + 1))")',
    )
    ..writeln('  kelola_c=0')
    // Every line is a path under $1; `x` (find failed) or nothing is not.
    ..writeln(r'  while IFS= read -r kelola_l; do')
    ..writeln(
      r'    case "$kelola_l" in /*) ;; *) kelola_no "$1" unreadable; '
      'return 1 ;; esac',
    )
    ..writeln(r'    kelola_c=$((kelola_c + 1))')
    ..writeln('  done <<KELOLA_END')
    ..writeln(r'$kelola_list')
    ..writeln('KELOLA_END')
    ..writeln(
      r'  if [ "$kelola_c" -gt "$kelola_left" ]; then kelola_no "$1" cap; '
      'return 1; fi',
    )
    ..writeln(r'  kelola_n=$((kelola_n + kelola_c))')
    ..writeln(
      '  if [ -n "\$(find "\$1" $pr -name "*\$kelola_nl*" -print 2>/dev/null '
      '| head -n 1)" ]; then kelola_no "\$1" unreadable; return 1; fi',
    )
    ..writeln(
      '  kelola_l=\$(find "\$1" $pr ! \\( $own \\) -print 2>/dev/null '
      '| head -n 1)',
    )
    ..writeln(
      r'  if [ -n "$kelola_l" ]; then kelola_no "$kelola_l" owner; return 1; '
      'fi',
    )
    ..writeln(
      '  kelola_l=\$(find "\$1" $pr ! -type l \\( -perm -020 -o -perm -002 '
      r'\) -print 2>/dev/null | head -n 1)',
    )
    ..writeln(
      r'  if [ -n "$kelola_l" ]; then kelola_no "$kelola_l" mode; return 1; '
      'fi',
    )
    // Links: owner checked above; now each target, hop by hop.
    ..writeln(r'  while IFS= read -r kelola_l; do')
    ..writeln(r'    [ -L "$kelola_l" ] || continue')
    ..writeln(r'    kelola_walk "$kelola_l" || return 1')
    ..writeln(
      r'    case "$kelola_l/" in "$cur"/*) kelola_no "$kelola_l" loop; '
      'return 1 ;; esac',
    )
    ..writeln(
      r'    if [ -d "$cur" ]; then kelola_q=$kelola_q$cur$kelola_nl; fi',
    )
    ..writeln('  done <<KELOLA_END')
    ..writeln(r'$kelola_list')
    ..writeln('KELOLA_END')
    ..writeln('}')
    // Scans $1 and every directory a link in it names, each once.
    ..writeln('kelola_scan() {')
    ..writeln(r'  kelola_q=$1$kelola_nl')
    ..writeln(r'  while [ -n "$kelola_q" ]; do')
    ..writeln(r'    kelola_d=${kelola_q%%"$kelola_nl"*}')
    ..writeln(r'    kelola_q=${kelola_q#*"$kelola_nl"}')
    ..writeln(
      r'    case "$kelola_nl$kelola_seen" in '
      r'*"$kelola_nl$kelola_d$kelola_nl"*) continue ;; esac',
    )
    ..writeln(r'    kelola_seen=$kelola_seen$kelola_d$kelola_nl')
    ..writeln(r'    kelola_tree "$kelola_d" || return 1')
    ..writeln('  done')
    ..writeln('}')
    // $1: a config root or module directory. $2: `opt` when it may be
    // absent (missing, or missing behind a clean chain).
    // Always walked, so an absent one is skipped only when the walk itself
    // ends at the missing component (every hop before it clean).
    ..writeln('kelola_root() {')
    ..writeln(r'  if ! kelola_walk "$1"; then')
    ..writeln(
      r'    if [ "$2" = opt ] && [ "$kelola_why" = missing ]; then return 0; '
      'fi',
    )
    ..writeln('    return 1')
    ..writeln('  fi')
    ..writeln(
      r'  if [ ! -d "$cur" ]; then kelola_no "$1" unreadable; return 1; fi',
    )
    ..writeln(r'  kelola_scan "$cur"')
    ..writeln('}')
    // $1: one file (envvars, a dump-named file). $2 as above.
    ..writeln('kelola_file() {')
    ..writeln(
      r'  if [ "$kelola_n" -ge "$kelola_cap" ]; then kelola_no "$1" cap; '
      'return 1; fi',
    )
    ..writeln(r'  kelola_n=$((kelola_n + 1))')
    ..writeln(r'  if kelola_walk "$1"; then return 0; fi')
    ..writeln(
      r'  if [ "$2" = opt ] && [ "$kelola_why" = missing ]; then return 0; fi',
    )
    ..writeln('  return 1')
    ..writeln('}')
    ..writeln('kelola_cfg() {')
    ..writeln('  kelola_n=0')
    ..writeln('  kelola_seen=')
    ..writeln('  kelola_q=')
    ..writeln('  kelola_at=')
    ..writeln('  kelola_why=');

  // Dump-named files first in Dart: one that cannot be checked, or too
  // many, fails before anything runs.
  final files = configFiles.toSet().toList();
  final bad = files.where((f) => !isGrantableWebPath(f)).firstOrNull;
  if (bad != null) {
    b.writeln('  kelola_no ${decoded(bad)} unreadable; return 1');
  } else if (files.length > webConfigTrustMaxEntries) {
    b.writeln('  kelola_no ${decoded(files.first)} cap; return 1');
  }

  if (id == ServiceId.apache) {
    b.writeln('  kelola_r=0');
    b.writeln(
      '  for kelola_m in '
      '${webApacheConfigRoots.map((r) => '"\$kelola_pre$r"').join(' ')}; do',
    );
    b
      ..writeln(r'    if [ -e "$kelola_m" ] || [ -L "$kelola_m" ]; then')
      ..writeln(r'      kelola_r=1')
      ..writeln(r'      kelola_root "$kelola_m" req || return 1')
      ..writeln('    fi')
      ..writeln('  done')
      ..writeln(
        '  if [ "\$kelola_r" = 0 ]; then kelola_no '
        '"\$kelola_pre${webApacheConfigRoots.first}" missing; return 1; fi',
      )
      ..writeln('  kelola_file "\$kelola_pre$webApacheEnvvars" opt || return 1');
    for (final d in webApacheModuleDirs) {
      b.writeln('  kelola_root "\$kelola_pre$d" opt || return 1');
    }
  } else {
    b
      ..writeln('  kelola_bin=${decoded(bin)}')
      // Host output from a binary that passed its check: used only as a
      // quoted variable, and only when it is a plain absolute path.
      ..writeln(
        r'  if ! kelola_v=$("$kelola_bin" -V 2>&1); then '
        r'kelola_no "$kelola_bin" unreadable; return 1; fi',
      )
      ..writeln('  kelola_croot=\$kelola_pre$webNginxDefaultConfigRoot')
      ..writeln(r'  case "$kelola_v" in')
      ..writeln(r'    *" --conf-path="*)')
      ..writeln(r'      kelola_cp=${kelola_v#*" --conf-path="}')
      ..writeln(r'      kelola_cp=${kelola_cp%%" "*}')
      ..writeln(r'      kelola_cp=${kelola_cp%%"$kelola_nl"*}')
      ..writeln(r'      case "$kelola_cp" in')
      ..writeln(
        r'        *[!A-Za-z0-9._/+@-]*|*..*|*//*) '
        r'kelola_no "$kelola_bin" unreadable; return 1 ;;',
      )
      ..writeln(r'        /?*/*) kelola_croot=${kelola_cp%/*} ;;')
      ..writeln(r'        *) kelola_no "$kelola_bin" unreadable; return 1 ;;')
      ..writeln('      esac ;;')
      ..writeln('  esac')
      ..writeln(r'  kelola_root "$kelola_croot" req || return 1');
    for (final d in webNginxModuleDirs) {
      b.writeln('  kelola_root "\$kelola_pre$d" opt || return 1');
    }
    b
      ..writeln(
        '  for kelola_m in "\$kelola_pre"$webNginxShareModulesGlob*; do',
      )
      ..writeln(r'    kelola_root "$kelola_m" opt || return 1')
      ..writeln('  done');
  }
  if (bad == null && files.length <= webConfigTrustMaxEntries) {
    for (final f in files) {
      b.writeln('  kelola_file ${decoded(f)} req || return 1');
    }
  }
  b
    ..writeln('}')
    ..writeln('KELOLA_CFG=0')
    ..writeln(
      "if kelola_cfg; then KELOLA_CFG=1; else printf '%s %s %s\\n' "
      "'$webGrantConfigMarker' "
      r'''"$(printf '%s' "$kelola_at" | base64 | tr -d '\n')" '''
      r'"${kelola_why:-unreadable}"; fi',
    );
  return b.toString();
}

List<String> _distinctPaths(List<String?> linePaths) {
  final out = <String>[];
  for (final p in linePaths) {
    if (p != null && !out.contains(p)) out.add(p);
  }
  return out;
}

/// Max symlinks followed per binary (Linux's own limit); more fails.
const webTrustMaxHops = 40;

final _ownerName = RegExp(r'^[a-z_][a-z0-9_-]{0,31}$');

/// Shell (for `set -eu`) that stops the grant unless every one of
/// [binaries] is trusted on the host, then checks each of [paths]. Each path
/// is walked one component at a time, following each symlink by hand (plain `readlink`, at most
/// [webTrustMaxHops]; a relative target resolves against the link's
/// directory), and:
/// - `/`, every directory passed through and the final file must be owned by
///   root and neither group- nor other-writable;
/// - every symlink passed through must be owned by root (a link's own mode
///   is always 0777, so only its owner counts; its directory is checked as
///   above, so nobody else can replace it).
///
/// So no hop of the chain sudo re-resolves on every run can be repointed by
/// anyone but root. Fail-closed: a missing tool, empty output, a missing
/// path, too many hops or a link target with a newline (which `\$(...)`
/// would cut) all count as untrusted. On the first failing binary it prints
/// [webGrantUntrustedMarker] and the path (base64) and exits 5, before the
/// sudoers file is read or written.
///
/// [paths] (cert and log files, passed as command arguments) get the same
/// walk, except that the final file only has to be a regular file: logs are
/// often owned by the server's user, and `tail` / `openssl` only read it.
/// Everything that decides which file that is (`/`, each directory, each
/// symlink, including a final symlink) is checked as above, so the login
/// user cannot point the path at another file such as `/etc/shadow`. Path
/// number `j` sets `KELOLA_Pj=1` when it passes; when it fails it prints
/// [webGrantSkippedMarker] and the path (base64) and the grant continues
/// without the lines naming it.
///
/// Plain `find`, no sudo: system binaries are readable. Only POSIX `find`
/// options that busybox also has (`-maxdepth`, `-user`, `-perm -mode`; not
/// `-perm /mode`). Binaries travel base64-encoded, never as shell text.
///
/// [owners] exists for tests only (so the permission checks run without
/// root); [buildWebGrantScript] always uses root.
String webBinaryTrustShell(
  List<String> binaries, {
  List<String> paths = const [],
  @visibleForTesting List<String> owners = const ['root'],
}) => _trustShell(binaries, paths, owners);

String _trustShell(
  List<String> binaries,
  List<String> paths,
  List<String> owners,
) {
  if (owners.isEmpty || !owners.every(_ownerName.hasMatch)) {
    throw ArgumentError.value(owners, 'owners');
  }
  String finds(String extra) => owners
      .map(
        (o) =>
            '[ -n "\$(find "\$1" -maxdepth 0 -user \'$o\'$extra '
            '2>/dev/null)" ]',
      )
      .join(' || ');
  final b = StringBuffer()
    // A directory or the final file.
    ..writeln('kelola_ok() { ${finds(' ! -perm -020 ! -perm -002')}; }')
    // A symlink: owner only.
    ..writeln('kelola_link_ok() { ${finds('')}; }')
    // A newline, for spotting one in a link target.
    ..writeln(r"kelola_nl=$(printf '\nx'); kelola_nl=${kelola_nl%x}")
    // Where and why the last walk failed (the config check reports it).
    ..writeln('kelola_at=')
    ..writeln('kelola_why=')
    ..writeln(r'kelola_no() { kelola_at=$1; kelola_why=$2; }')
    ..writeln(
      r'kelola_bad() { kelola_at=$1; '
      r'if kelola_link_ok "$1"; then kelola_why=mode; '
      'else kelola_why=owner; fi; }',
    )
    // $1: the path. $2: `path` for a cert or log (final file: any owner).
    ..writeln('kelola_walk() {')
    ..writeln(
      r'  case "$1" in /*) ;; *) kelola_no "$1" unreadable; return 1 ;; esac',
    )
    ..writeln('  kelola_ok / || { kelola_bad /; return 1; }')
    // cur: resolved, symlink-free prefix ('' = /). rest: still to walk.
    ..writeln('  cur=')
    ..writeln(r'  rest=${1#/}')
    ..writeln('  hops=0')
    ..writeln('  last=')
    ..writeln(r'  while [ -n "$rest" ]; do')
    ..writeln(r'    case "$rest" in')
    ..writeln(r'      */*) c=${rest%%/*}; rest=${rest#*/} ;;')
    ..writeln(r'      *) c=$rest; rest= ;;')
    ..writeln('    esac')
    ..writeln(r'    case "$c" in')
    ..writeln("      ''|.) continue ;;")
    ..writeln(r'      ..) cur=${cur%/*}; last=dir; continue ;;')
    ..writeln('    esac')
    ..writeln(r'    cand=$cur/$c')
    ..writeln(r'    if [ -L "$cand" ]; then')
    ..writeln(
      r'      kelola_link_ok "$cand" || { kelola_no "$cand" owner; return 1; }',
    )
    ..writeln(r'      hops=$((hops + 1))')
    ..writeln(
      '      [ "\$hops" -le $webTrustMaxHops ] || '
      '{ kelola_no "\$cand" loop; return 1; }',
    )
    // `x` keeps readlink's own trailing newline, so a target that itself
    // ends in a newline is seen (and refused) instead of cut.
    ..writeln(
      r'      t=$(readlink "$cand" 2>/dev/null && echo x) || '
      r'{ kelola_no "$cand" unreadable; return 1; }',
    )
    ..writeln(r'      t=${t%x}')
    ..writeln(
      r'      case "$t" in *"$kelola_nl") t=${t%?} ;; '
      r'*) kelola_no "$cand" unreadable; return 1 ;; esac',
    )
    ..writeln(
      r'      case "$t" in *"$kelola_nl"*) kelola_no "$cand" unreadable; '
      'return 1 ;; esac',
    )
    ..writeln(
      r'      [ -n "$t" ] || { kelola_no "$cand" unreadable; return 1; }',
    )
    ..writeln(r'      case "$t" in /*) cur=; t=${t#/} ;; esac')
    ..writeln(r'      if [ -n "$rest" ]; then rest=$t/$rest; else rest=$t; fi')
    ..writeln(r'    elif [ -e "$cand" ]; then')
    ..writeln(r'      if [ -z "$rest" ] && [ "${2-}" = path ]; then')
    ..writeln(
      r'        [ -f "$cand" ] || { kelola_no "$cand" unreadable; return 1; }',
    )
    ..writeln(r'      elif ! kelola_ok "$cand"; then')
    ..writeln(r'        kelola_bad "$cand"; return 1')
    ..writeln('      fi')
    ..writeln(r'      cur=$cand')
    ..writeln('      last=file')
    ..writeln('    else')
    ..writeln(r'      kelola_no "$cand" missing; return 1')
    ..writeln('    fi')
    ..writeln('  done')
    // Ends on a checked path, never on `/` or a `..`; a cert or log on a
    // regular file.
    ..writeln(
      r'  [ -n "$cur" ] && [ "$last" = file ] || '
      r'{ kelola_no "$1" unreadable; return 1; }',
    )
    ..writeln(r'  [ "${2-}" != path ] || [ -f "$cur" ]')
    ..writeln('}')
    ..writeln('kelola_trust() {')
    ..writeln(r'  if kelola_walk "$1"; then return 0; fi')
    ..writeln(
      "  printf '%s %s\\n' '$webGrantUntrustedMarker' "
      r'''"$(printf '%s' "$1" | base64 | tr -d '\n')"''',
    )
    ..writeln('  exit 5')
    ..writeln('}');
  for (final bin in binaries) {
    final b64 = base64Encode(utf8.encode(bin));
    b.writeln("kelola_trust \"\$(printf '%s' '$b64' | base64 -d)\"");
  }
  for (final (j, p) in paths.indexed) {
    final b64 = base64Encode(utf8.encode(p));
    b
      ..writeln('KELOLA_P$j=0')
      ..writeln(
        'if kelola_walk "\$(printf \'%s\' \'$b64\' | base64 -d)" path; '
        'then KELOLA_P$j=1; else '
        "printf '%s %s\\n' '$webGrantSkippedMarker' '$b64'; fi",
      );
  }
  return b.toString();
}

/// The binary named after [webGrantUntrustedMarker] in [stdout], if any:
/// the decoded path when it is a plain absolute path, else `a binary`.
/// Null when the marker is absent.
String? webGrantUntrustedBinary(String stdout) {
  for (final line in const LineSplitter().convert(stdout)) {
    if (!line.startsWith('$webGrantUntrustedMarker ') &&
        line != webGrantUntrustedMarker) {
      continue;
    }
    final raw = line.substring(webGrantUntrustedMarker.length).trim();
    try {
      final path = utf8.decode(base64Decode(raw));
      if (isGrantableWebPath(path)) return path;
    } on FormatException {
      // Fall through.
    }
    return 'a binary';
  }
  return null;
}

String webGrantUntrustedCopy(String binary) =>
    'Not granted: $binary is not root-owned or is writable by others.';

/// The paths named after each [webGrantSkippedMarker] in [stdout], in
/// order, once each: the decoded path when it is a plain absolute path,
/// else `a path`.
List<String> webGrantSkippedPaths(String stdout) {
  final out = <String>[];
  for (final line in const LineSplitter().convert(stdout)) {
    if (!line.startsWith('$webGrantSkippedMarker ') &&
        line != webGrantSkippedMarker) {
      continue;
    }
    final raw = line.substring(webGrantSkippedMarker.length).trim();
    var path = 'a path';
    try {
      final p = utf8.decode(base64Decode(raw));
      if (isGrantableWebPath(p)) path = p;
    } on FormatException {
      // Stays `a path`.
    }
    if (!out.contains(path)) out.add(path);
  }
  return out;
}

String webGrantSkippedCopy(String path) =>
    'Not granted: $path is in a directory that is not root-owned or is '
    'writable by others.';

/// [webGrantSkippedCopy] split around the path, so a screen can set the
/// path in mono.
({String lead, String path, String tail}) webGrantSkippedCopyParts(
  String path,
) => (
  lead: 'Not granted: ',
  path: path,
  tail:
      ' is in a directory that is not root-owned or is writable by others.',
);

/// The refusal after [webGrantConfigMarker] in [stdout] (the first one), or
/// null without one. Host text is only displayed: the path is kept when it
/// is a plain absolute path (else `a config file`), an unknown reason reads
/// as [WebConfigRefusalReason.unreadable].
WebGrantConfigRefusal? webGrantConfigRefusal(String stdout) {
  for (final line in const LineSplitter().convert(stdout)) {
    if (!line.startsWith('$webGrantConfigMarker ') &&
        line != webGrantConfigMarker) {
      continue;
    }
    final words = line
        .substring(webGrantConfigMarker.length)
        .trim()
        .split(' ');
    var path = 'a config file';
    try {
      final p = utf8.decode(base64Decode(words.first));
      if (isGrantableWebPath(p)) path = p;
    } on FormatException {
      // Stays `a config file`.
    }
    var reason = WebConfigRefusalReason.unreadable;
    if (words.length == 2) {
      for (final r in WebConfigRefusalReason.values) {
        if (r.name == words[1]) reason = r;
      }
    }
    return WebGrantConfigRefusal(path: path, reason: reason);
  }
  return null;
}

/// `Config test not granted: <path> <why>.`, split around the path.
({String lead, String path, String tail}) webGrantConfigCopyParts(
  WebGrantConfigRefusal r,
) => (
  lead: 'Config test not granted: ',
  path: r.path,
  tail: switch (r.reason) {
    WebConfigRefusalReason.owner => ' is not root-owned.',
    WebConfigRefusalReason.mode => ' is writable by group or others.',
    WebConfigRefusalReason.cap => ' has too many config files to check.',
    WebConfigRefusalReason.loop => ' is a symlink loop.',
    WebConfigRefusalReason.missing => ' is missing.',
    WebConfigRefusalReason.unreadable => ' could not be checked.',
  },
);

String webGrantConfigCopy(WebGrantConfigRefusal r) {
  final p = webGrantConfigCopyParts(r);
  return '${p.lead}${p.path}${p.tail}';
}

/// What the host left out of a web grant whose other lines were installed.
class WebGrantResult {
  const WebGrantResult({this.skipped = const [], this.config});

  /// Cert and log paths whose lines were left out ([webGrantSkippedPaths]).
  final List<String> skipped;

  /// Why the config test lines were left out, or null when they went in
  /// (or were not asked for).
  final WebGrantConfigRefusal? config;
}

/// Every line of a web grant was left out by the host-side checks, so
/// nothing was read or written. [message] is the copy, one line each.
class WebGrantRefusedException extends KelolaException {
  WebGrantRefusedException({this.skipped = const [], this.config})
    : super(
        [
          if (config != null) webGrantConfigCopy(config),
          ...skipped.map(webGrantSkippedCopy),
        ].join('\n'),
      );

  final List<String> skipped;
  final WebGrantConfigRefusal? config;
}
