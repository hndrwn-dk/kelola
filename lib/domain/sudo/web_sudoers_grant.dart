import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// Exit status of the grant script when every line was skipped, so nothing
/// was read or written.
const webGrantNothingExit = 6;

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
  });

  final ServiceId id;
  final String user;
  final List<String> lines;

  /// For each of [lines], the cert or log path it names, or null (the
  /// server binary's lines). The grant script checks each path on the host
  /// and leaves out the lines of a path that fails.
  final List<String?> linePaths;

  /// Null when [webGrantLines] gives no line.
  static WebSudoersGrant? tryCreate({
    required String user,
    required ServiceId id,
    required Map<String, String> binaries,
    Map<String, String> toolPaths = const {},
    List<String> certPaths = const [],
    String? errorLog,
    String? accessLog,
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
    return WebSudoersGrant._(
      id: id,
      user: user,
      lines: List.unmodifiable([for (final e in entries) e.line]),
      linePaths: List.unmodifiable([for (final e in entries) e.path]),
    );
  }

  /// Each distinct binary the lines name, in order.
  List<String> get binaries {
    const sep = ' NOPASSWD: ';
    final out = <String>[];
    for (final l in lines) {
      final cmd = l.substring(l.indexOf(sep) + sep.length);
      final bin = cmd.substring(0, cmd.indexOf(' '));
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
/// [trustOwners] exists for tests only (see [webBinaryTrustShell]).
String buildWebGrantScript(
  WebSudoersGrant g, {
  @visibleForTesting List<String> trustOwners = const ['root'],
}) {
  final paths = _distinctPaths(g.linePaths);
  String? gate(String? p) =>
      p == null ? null : '[ "\$KELOLA_P${paths.indexOf(p)}" = 1 ]';
  final gates = [for (final p in g.linePaths) gate(p)];
  final stop = gates.every((c) => c != null)
      ? '${paths.indexed.map((e) => '[ "\$KELOLA_P${e.$1}" = 1 ]').join(' || ')}'
            ' || exit $webGrantNothingExit\n'
      : '';
  return buildSudoersGrantScript(
    path: kelolaWebSudoersPath,
    header: '# Kelola: lens read rules, one command per line. Safe to edit.',
    lines: g.lines,
    okMarker: webGrantOkMarker,
    preamble: _trustShell(g.binaries, paths, trustOwners) + stop,
    lineConditions: gates,
  );
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
    // $1: the path. $2: `path` for a cert or log (final file: any owner).
    ..writeln('kelola_walk() {')
    ..writeln(r'  case "$1" in /*) ;; *) return 1 ;; esac')
    ..writeln('  kelola_ok / || return 1')
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
    ..writeln(r'      kelola_link_ok "$cand" || return 1')
    ..writeln(r'      hops=$((hops + 1))')
    ..writeln('      [ "\$hops" -le $webTrustMaxHops ] || return 1')
    // `x` keeps readlink's own trailing newline, so a target that itself
    // ends in a newline is seen (and refused) instead of cut.
    ..writeln(r'      t=$(readlink "$cand" 2>/dev/null && echo x) || return 1')
    ..writeln(r'      t=${t%x}')
    ..writeln(
      r'      case "$t" in *"$kelola_nl") t=${t%?} ;; *) return 1 ;; esac',
    )
    ..writeln(r'      case "$t" in *"$kelola_nl"*) return 1 ;; esac')
    ..writeln(r'      [ -n "$t" ] || return 1')
    ..writeln(r'      case "$t" in /*) cur=; t=${t#/} ;; esac')
    ..writeln(r'      if [ -n "$rest" ]; then rest=$t/$rest; else rest=$t; fi')
    ..writeln(r'    elif [ -e "$cand" ]; then')
    ..writeln(r'      if [ -z "$rest" ] && [ "${2-}" = path ]; then')
    ..writeln(r'        [ -f "$cand" ] || return 1')
    ..writeln(r'      elif ! kelola_ok "$cand"; then')
    ..writeln('        return 1')
    ..writeln('      fi')
    ..writeln(r'      cur=$cand')
    ..writeln('      last=file')
    ..writeln('    else')
    ..writeln('      return 1')
    ..writeln('    fi')
    ..writeln('  done')
    // Ends on a checked path, never on `/` or a `..`; a cert or log on a
    // regular file.
    ..writeln(r'  [ -n "$cur" ] && [ "$last" = file ] || return 1')
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
