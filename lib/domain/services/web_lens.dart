import 'service_catalog.dart';

/// M52: web lens data model (nginx and Apache httpd). Data only; severity
/// (`overall`, `findings`) is added with the severity table in a later task.

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

class WebFinding {
  const WebFinding({required this.level, required this.message, this.subject});

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
}
