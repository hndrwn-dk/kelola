import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/sudo/unit_sudoers_grant.dart';

/// M52 §7b: exact read rules for the web lenses. Written only from a lens,
/// never by Enable Kelola sudo, so it never reads as outdated rules there.
const kelolaWebSudoersPath = '/etc/sudoers.d/kelola-web';

const webGrantOkMarker = 'KELOLA_WEB_GRANT_OK';

/// Root-owned system directories. A NOPASSWD rule on a binary the login user
/// can replace would be a root shell, and binary paths come from the host's
/// own output, so only these directories are ever granted.
const webGrantSystemDirs = {
  '/usr/bin',
  '/usr/sbin',
  '/bin',
  '/sbin',
  '/usr/local/bin',
  '/usr/local/sbin',
};

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
}) {
  if (!_userName.hasMatch(user)) return const [];
  if (id != ServiceId.nginx && id != ServiceId.apache) return const [];
  final commands = <String>[];

  final names = webConfigTestBinaryNames(id);
  final bin = safeWebBinary(binaries, names);
  if (bin != null && names.any((n) => isGrantableWebBinary(bin, n))) {
    commands
      ..add('$bin -t')
      ..add(id == ServiceId.apache ? '$bin -S' : '$bin -T');
  }

  final openssl = toolPaths['openssl'];
  if (isGrantableWebBinary(openssl, 'openssl')) {
    for (final p in certPaths) {
      if (!isGrantableWebPath(p)) continue;
      commands.add(
        '$openssl x509 -noout -enddate -subject -ext subjectAltName -in $p',
      );
    }
  }

  final tail = toolPaths['tail'];
  if (isGrantableWebBinary(tail, 'tail')) {
    if (errorLog != null && isGrantableWebPath(errorLog)) {
      commands.add('$tail -n 60 $errorLog');
    }
    if (accessLog != null && isGrantableWebPath(accessLog)) {
      commands.add('$tail -n 2000 $accessLog');
    }
  }

  final seen = <String>{};
  return [
    for (final c in commands)
      if (seen.add(c)) '$user ALL=(root) NOPASSWD: $c',
  ];
}

/// Lens read rules for one web server, shown to the user before they are
/// written to [kelolaWebSudoersPath].
class WebSudoersGrant {
  const WebSudoersGrant._({
    required this.id,
    required this.user,
    required this.lines,
  });

  final ServiceId id;
  final String user;
  final List<String> lines;

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
    final lines = webGrantLines(
      user: user,
      id: id,
      binaries: binaries,
      toolPaths: toolPaths,
      certPaths: certPaths,
      errorLog: errorLog,
      accessLog: accessLog,
    );
    if (lines.isEmpty) return null;
    return WebSudoersGrant._(
      id: id,
      user: user,
      lines: List.unmodifiable(lines),
    );
  }

  bool get hasCertLines => lines.any((l) => l.contains(' x509 '));

  String get linesHash =>
      sha256.convert(utf8.encode(lines.join('\n'))).toString();
}

/// Remote sh that reads the sudo password on stdin (one line) and adds the
/// grant's lines to [kelolaWebSudoersPath], keeping the lines already there.
/// Same script as the per-unit grant ([buildSudoersGrantScript]).
String buildWebGrantScript(WebSudoersGrant g) {
  return buildSudoersGrantScript(
    path: kelolaWebSudoersPath,
    header: '# Kelola: lens read rules, one command per line. Safe to edit.',
    lines: g.lines,
    okMarker: webGrantOkMarker,
  );
}
