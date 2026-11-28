import 'package:kelola/design/kelola_theme.dart';

import 'service_catalog.dart';

/// M52: web lens data model (nginx and Apache httpd), with the §5c severity
/// table in [WebLens.findings].

enum WebLensSection { active, configTest, dump, certs, errorLog, access }

/// One virtual host. Never carries private key paths.
class WebVhost {
  const WebVhost({
    this.serverNames = const [],
    this.listen = const [],
    this.tls = false,
    this.root,
    this.certPath,
    this.certPaths = const [],
    this.sourceFile = '',
    this.inherited = false,
  });

  /// Empty when the block has no `server_name`; `['_']` only when the
  /// config says `_`.
  final List<String> serverNames;

  /// e.g. `['443 ssl', '[::]:80']`.
  final List<String> listen;
  final bool tls;
  final String? root;
  final String? certPath;

  /// Every `ssl_certificate` (RSA + ECDSA pairs), in order; [certPath] is the
  /// first.
  final List<String> certPaths;
  final String sourceFile;

  /// Fix 3: the vhost sets no certificate of its own; [certPath] is the one
  /// it inherits (nginx `http {}` level, Apache server config).
  final bool inherited;

  @override
  String toString() =>
      'WebVhost(serverNames: $serverNames, listen: $listen, tls: $tls, '
      'root: $root, certPath: $certPath, inherited: $inherited, '
      'sourceFile: $sourceFile)';
}

class WebCert {
  const WebCert({
    required this.path,
    this.notAfter,
    this.subjectCn,
    this.sans = const [],
  });

  final String path;

  /// null = unreadable.
  final DateTime? notAfter;
  final String? subjectCn;
  final List<String> sans;

  /// Whole days until expiry (floor); negative when expired; null when
  /// [notAfter] is unknown.
  int? daysLeft(DateTime now) {
    final end = notAfter;
    if (end == null) return null;
    final diff = end.difference(now);
    return (diff.inMicroseconds / Duration.microsecondsPerDay).floor();
  }
}

/// `stat -L -c '%U %G %a'` of a log file, as the host printed it and the
/// parser validated it (fix 2). Only used to suggest the adm group.
class WebLogStat {
  const WebLogStat({
    required this.owner,
    required this.group,
    required this.mode,
  });

  final String owner;
  final String group;

  /// Octal, 3 or 4 digits (`640`, `2750`).
  final String mode;

  /// Group read bit (`0o040`) of [mode]; false when [mode] is not octal.
  bool get groupReadable {
    final m = int.tryParse(mode, radix: 8);
    return m != null && m & 0x20 != 0;
  }
}

enum WebFindingLevel { failed, warning, fact }

/// Which §5c row produced a finding; screens branch on this, never on copy.
enum WebFindingKind {
  configTestFailed,
  serviceNotActive,
  certExpired,
  certExpiring,
  certUnreadable,
  http5xx,
  listens443WithoutCert,
  defaultVhostOnly,

  /// Apache: a cert could not be tied to a vhost (fix 3). A fact: unknown is
  /// not a warning.
  certsUnattributed,
}

class WebFinding {
  const WebFinding({
    required this.kind,
    required this.level,
    required this.message,
    this.subject,
  });

  final WebFindingKind kind;
  final WebFindingLevel level;
  final String message;
  final String? subject;
}

class WebLens {
  WebLens({
    required this.id,
    required this.readAt,
    this.activeState,
    this.configOk,
    this.configErrors = const [],
    this.vhosts = const [],
    this.certsByPath = const {},
    this.errorLogTail = const [],
    this.statusCounts = const {},
    this.sectionErrors = const {},
    this.toolPaths = const {},
    this.errorLogPath,
    this.accessLogPath,
    this.configFiles = const [],
    this.errorLogStat,
    this.accessLogStat,
    this.loginGroups,
    this.vhostCertsUnlinked = false,
    this.configTestViaSudo = false,
  });

  final ServiceId id;
  final String? activeState;

  /// null = the test could not run.
  final bool? configOk;

  /// The config test ran through `sudo -n` (the login alone could not run
  /// it) and sudo did not refuse: a NOPASSWD rule allowed it. The lens then
  /// checks whether that rule is an outdated config-test grant.
  final bool configTestViaSudo;
  final List<String> configErrors;
  final List<WebVhost> vhosts;
  final Map<String, WebCert> certsByPath;
  final List<String> errorLogTail;

  /// HTTP status -> count, e.g. `200 -> 1543`.
  final Map<int, int> statusCounts;
  final Map<WebLensSection, String> sectionErrors;
  final DateTime readAt;

  /// Tool name -> absolute path (openssl, tail, ...), used for the sudo grant.
  final Map<String, String> toolPaths;
  final String? errorLogPath;
  final String? accessLogPath;

  /// Config files the dump named, as the host printed them: nginx's
  /// `# configuration file` sections, Apache's vhost files from `-S`. The
  /// read grant checks each on the host before it adds the config test.
  final List<String> configFiles;

  /// Owner, group and mode of the error / access log; null when the probe
  /// could not stat it (directory not traversable, file missing, junk).
  final WebLogStat? errorLogStat;
  final WebLogStat? accessLogStat;

  /// The login's groups (`id -nG`); null = unknown, never guessed.
  final List<String>? loginGroups;

  /// Apache (fix 3): a certificate was read that could not be tied to any
  /// `-S` vhost or to the server config (its `<VirtualHost>` line matched no
  /// vhost, the probe's link cap was reached, or it printed no links).
  /// Which vhost has it is unknown, so no vhost is called one without a
  /// certificate and none is given the global one; a fact says so.
  final bool vhostCertsUnlinked;

  /// Worst finding (facts never count). [HealthStatus.unknown] only when no
  /// section at all could be read.
  HealthStatus get overall {
    final all = findings;
    if (all.any((f) => f.level == WebFindingLevel.failed)) {
      return HealthStatus.failed;
    }
    if (all.any((f) => f.level == WebFindingLevel.warning)) {
      return HealthStatus.warning;
    }
    // Starting or reloading: not a failure, but not known healthy yet.
    if (_transitionalStates.contains(activeState)) return HealthStatus.unknown;
    // An empty, error-free cert section alone (no TLS) is not a read.
    final readSomething =
        WebLensSection.values.any(
          (s) => s != WebLensSection.certs && !sectionErrors.containsKey(s),
        ) ||
        certsByPath.values.any((c) => c.notAfter != null);
    return readSomething ? HealthStatus.healthy : HealthStatus.unknown;
  }

  /// Spec §5c, ordered failed, warning, fact.
  List<WebFinding> get findings {
    final failed = <WebFinding>[];
    final warning = <WebFinding>[];
    final facts = <WebFinding>[];

    if (configOk == false) {
      failed.add(
        WebFinding(
          kind: WebFindingKind.configTestFailed,
          level: WebFindingLevel.failed,
          message: 'Config test failed',
          subject: configErrors.isEmpty ? null : configErrors.first,
        ),
      );
    }

    final state = activeState;
    if (state != null &&
        !_runningStates.contains(state) &&
        !_transitionalStates.contains(state)) {
      failed.add(
        WebFinding(
          kind: WebFindingKind.serviceNotActive,
          level: WebFindingLevel.failed,
          message: 'Service not active',
          subject: state,
        ),
      );
    }

    // Certs not tied to a vhost (stream level, an unlinked Apache vhost) are
    // still served. Check every cert read.
    for (final cert in certsByPath.values) {
      final days = cert.daysLeft(readAt);
      if (days == null) {
        facts.add(
          WebFinding(
            kind: WebFindingKind.certUnreadable,
            level: WebFindingLevel.fact,
            message: 'Certificate unreadable',
            subject: cert.path,
          ),
        );
        continue;
      }
      final subject = _certSubject(cert);
      if (days < 0) {
        failed.add(
          WebFinding(
            kind: WebFindingKind.certExpired,
            level: WebFindingLevel.failed,
            message: 'Certificate expired',
            subject: subject,
          ),
        );
      } else if (days <= 7) {
        failed.add(
          WebFinding(
            kind: WebFindingKind.certExpiring,
            level: WebFindingLevel.failed,
            message: 'Certificate expires in ${_days(days)}',
            subject: subject,
          ),
        );
      } else if (days <= 21) {
        warning.add(
          WebFinding(
            kind: WebFindingKind.certExpiring,
            level: WebFindingLevel.warning,
            message: 'Certificate expires in ${_days(days)}',
            subject: subject,
          ),
        );
      }
    }
    // A vhost cert that was never read (path refused or capped).
    final missing = <String>{
      for (final v in vhosts)
        for (final p in v.certPaths)
          if (!certsByPath.containsKey(p)) p,
    };
    for (final p in missing) {
      facts.add(
        WebFinding(
          kind: WebFindingKind.certUnreadable,
          level: WebFindingLevel.fact,
          message: 'Certificate unreadable',
          subject: p,
        ),
      );
    }

    final total = statusCounts.values.fold<int>(0, (a, b) => a + b);
    var errors5xx = 0;
    statusCounts.forEach((code, n) {
      if (code >= 500 && code <= 599) errors5xx += n;
    });
    if (total >= 100 && errors5xx * 100 >= total * 5) {
      final pct = (errors5xx * 100 / total).toStringAsFixed(1);
      warning.add(
        WebFinding(
          kind: WebFindingKind.http5xx,
          level: WebFindingLevel.warning,
          message: '5xx at $pct% of the last $total requests',
        ),
      );
    }

    for (final v in vhosts) {
      if (!v.listen.any(_listensOn443)) continue;
      // Own or inherited (fix 3). Apache: never when the cert section failed
      // or a cert could not be tied to its vhost.
      final noCert = id == ServiceId.apache
          ? v.certPaths.isEmpty &&
                !sectionErrors.containsKey(WebLensSection.certs) &&
                !vhostCertsUnlinked
          : v.certPaths.isEmpty;
      if (noCert) {
        warning.add(
          WebFinding(
            kind: WebFindingKind.listens443WithoutCert,
            level: WebFindingLevel.warning,
            message: 'Listens on 443 without a certificate',
            subject: v.serverNames.isEmpty ? v.sourceFile : v.serverNames.first,
          ),
        );
      }
    }

    if (vhostCertsUnlinked) {
      facts.add(
        const WebFinding(
          kind: WebFindingKind.certsUnattributed,
          level: WebFindingLevel.fact,
          message: 'Some certificates could not be tied to a vhost.',
        ),
      );
    }

    if (vhosts.isNotEmpty &&
        vhosts.every((v) => v.serverNames.every(_isDefaultName))) {
      facts.add(
        const WebFinding(
          kind: WebFindingKind.defaultVhostOnly,
          level: WebFindingLevel.fact,
          message: 'Default vhost only',
        ),
      );
    }

    return [...failed, ...warning, ...facts];
  }

  String _certSubject(WebCert cert) {
    for (final v in vhosts) {
      if (v.certPaths.contains(cert.path) && v.serverNames.isNotEmpty) {
        return v.serverNames.first;
      }
    }
    return cert.subjectCn ?? cert.path;
  }
}

/// `running` is Docker's State.Status (M52c container lens).
const _runningStates = {'active', 'refreshing', 'started', 'running'};

/// systemd on the way up or mid-reload: no finding either way.
const _transitionalStates = {'activating', 'reloading'};

String _days(int d) => d == 1 ? '1 day' : '$d days';

/// `443`, `443 ssl`, `[::]:443 ssl http2`, `0.0.0.0:443`, `*:443`.
bool _listensOn443(String listen) {
  final first = listen.trim().split(RegExp(r'\s+')).first;
  final i = first.lastIndexOf(':');
  final port = i >= 0 ? first.substring(i + 1) : first;
  return port == '443';
}

/// `_`, a bare IP or `localhost`: the catch-all, not a named site.
bool _isDefaultName(String name) {
  if (name.isEmpty || name == '_' || name == 'localhost') return true;
  if (name.contains(':')) return true; // IPv6 literal
  return RegExp(r'^[0-9.]+$').hasMatch(name);
}
