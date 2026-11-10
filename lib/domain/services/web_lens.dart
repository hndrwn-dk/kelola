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

  @override
  String toString() =>
      'WebVhost(serverNames: $serverNames, listen: $listen, tls: $tls, '
      'root: $root, certPath: $certPath, sourceFile: $sourceFile)';
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
  });

  final ServiceId id;
  final String? activeState;

  /// null = the test could not run.
  final bool? configOk;
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

    // -S cannot tie Apache certs to vhosts; nginx certs not referenced by a
    // vhost (http{} or stream level) are still served. Check every cert read.
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
      final noCert = id == ServiceId.apache
          // Apache: only when the config has no certificate at all.
          ? certsByPath.isEmpty &&
                !sectionErrors.containsKey(WebLensSection.certs)
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

const _runningStates = {'active', 'refreshing', 'started'};

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
