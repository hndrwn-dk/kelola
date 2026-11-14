import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/config_tested_reload_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/services/apache_vhosts_parser.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';
import 'package:kelola/domain/services/web_lens.dart';
import 'package:kelola/domain/services/web_lens_parser.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_unit_action.dart';
import 'package:kelola/presentation/widgets/enable_kelola_sudo_flow.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

/// Certs at or under this many days left count as expiring (spec §5c).
const webCertExpiringDays = 21;

/// Fix 3: the note beside a certificate a vhost inherits.
String webInheritedCertNote(ServiceId id) => id == ServiceId.apache
    ? 'inherited from server config'
    : 'inherited from http {}';

/// Error log lines shown inline; the sheet has the full tail.
const _inlineLogLines = 8;

/// M52 §5d vhost filter pills.
enum VhostFilter { all, tls, expiring, noTls }

/// True when any of [v]'s certificates expires within
/// [webCertExpiringDays] (expired included). Unreadable certs do not count.
bool vhostExpiring(WebLens l, WebVhost v, DateTime now) {
  for (final p in v.certPaths) {
    final days = l.certsByPath[p]?.daysLeft(now);
    if (days != null && days <= webCertExpiringDays) return true;
  }
  return false;
}

List<WebVhost> filterVhosts(WebLens l, VhostFilter f, DateTime now) {
  return switch (f) {
    VhostFilter.all => List.of(l.vhosts),
    VhostFilter.tls => [
      for (final v in l.vhosts)
        if (v.tls) v,
    ],
    VhostFilter.expiring => [
      for (final v in l.vhosts)
        if (vhostExpiring(l, v, now)) v,
    ],
    VhostFilter.noTls => [
      for (final v in l.vhosts)
        if (!v.tls) v,
    ],
  };
}

String vhostFilterLabel(VhostFilter f) => switch (f) {
  VhostFilter.all => 'all',
  VhostFilter.tls => 'tls',
  VhostFilter.expiring => 'expiring',
  VhostFilter.noTls => 'no tls',
};

String vhostEmptyCopy(VhostFilter f) => switch (f) {
  VhostFilter.all => 'No vhosts found.',
  VhostFilter.tls => 'No TLS vhosts.',
  VhostFilter.expiring => 'No vhosts expiring in $webCertExpiringDays days.',
  VhostFilter.noTls => 'No vhosts without TLS.',
};

/// Vhosts stat: `unknown` when the dump could not be read at all.
String webVhostsValue(WebLens l) {
  if (l.vhosts.isEmpty && l.sectionErrors.containsKey(WebLensSection.dump)) {
    return 'unknown';
  }
  return '${l.vhosts.length}';
}

/// Certs stat: `unknown` when the certs section failed (even if a readable
/// cert is expiring; its finding still shows in the band) or TLS vhosts have
/// no readable certificate; else `<k> expiring` or `ok`.
String webCertsValue(WebLens l, DateTime now) {
  var expiring = 0;
  var readable = 0;
  for (final c in l.certsByPath.values) {
    final d = c.daysLeft(now);
    if (d == null) continue;
    readable++;
    if (d <= webCertExpiringDays) expiring++;
  }
  if (l.sectionErrors.containsKey(WebLensSection.certs)) return 'unknown';
  if (expiring > 0) return '$expiring expiring';
  if (readable == 0 && l.vhosts.any((v) => v.tls)) return 'unknown';
  return 'ok';
}

/// 5xx share of the access-log sample, `0.4%`; `unknown` when the access
/// section failed or holds no requests.
String web5xxValue(WebLens l) {
  if (l.sectionErrors.containsKey(WebLensSection.access)) return 'unknown';
  final total = l.statusCounts.values.fold<int>(0, (a, b) => a + b);
  if (total <= 0) return 'unknown';
  var errors = 0;
  l.statusCounts.forEach((code, n) {
    if (code >= 500 && code <= 599) errors += n;
  });
  return '${(errors * 100 / total).toStringAsFixed(1)}%';
}

/// Failed and warning findings, failed first, each group in domain order.
/// The band headline is the first; never relies on [WebLens.findings] order.
List<WebFinding> bandFindings(List<WebFinding> findings) => [
  for (final f in findings)
    if (f.level == WebFindingLevel.failed) f,
  for (final f in findings)
    if (f.level == WebFindingLevel.warning) f,
];

/// True when the §5c 5xx finding fires.
bool web5xxFires(List<WebFinding> findings) => findings.any(
  (f) => f.kind == WebFindingKind.http5xx && f.level != WebFindingLevel.fact,
);

/// Band copy when nothing failed or warns.
String webOkSummary(WebLens l, DateTime now) {
  final config = l.configOk == null ? 'Config not tested' : 'Config OK';
  final vhosts = webVhostsValue(l);
  final vhostsText = vhosts == 'unknown'
      ? 'vhosts unknown'
      : vhosts == '1'
      ? '1 vhost'
      : '$vhosts vhosts';
  final certs = webCertsValue(l, now) == 'unknown'
      ? 'certs unknown'
      : 'certs fine';
  return '$config · $vhostsText · $certs';
}

/// One error-log line split for [JournalLogLine]: nginx
/// `2026/11/10 01:31:42 [error] …` or Apache `[Mon Nov 10 …] [core:error] …`.
/// Anything else is the whole line as an info message.
({String timestamp, String message, JournalLineKind kind}) webErrorLogLine(
  String line,
) {
  final nginx = RegExp(
    r'^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(\w+)\] ?(.*)$',
  ).firstMatch(line);
  if (nginx != null) {
    return (
      timestamp: nginx.group(1)!,
      message: nginx.group(3)!,
      kind: _logKind(nginx.group(2)!),
    );
  }
  final apache = RegExp(r'^\[([^\]]+)\] \[([^\]]*)\] ?(.*)$').firstMatch(line);
  if (apache != null) {
    final level = apache.group(2)!;
    final i = level.lastIndexOf(':');
    return (
      timestamp: apache.group(1)!,
      message: apache.group(3)!,
      kind: _logKind(i >= 0 ? level.substring(i + 1) : level),
    );
  }
  return (timestamp: '', message: line, kind: JournalLineKind.info);
}

JournalLineKind _logKind(String level) {
  switch (level.toLowerCase()) {
    case 'emerg':
    case 'alert':
    case 'crit':
    case 'error':
      return JournalLineKind.error;
    case 'warn':
    case 'warning':
      return JournalLineKind.warning;
    default:
      return JournalLineKind.info;
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// `2026-12-01 08:30 UTC`.
String webCertDate(DateTime t) {
  final u = t.toUtc();
  return '${u.year}-${_two(u.month)}-${_two(u.day)} '
      '${_two(u.hour)}:${_two(u.minute)} UTC';
}

String _daysLeftCopy(int d) {
  if (d < 0) {
    final ago = -d;
    return ago == 1 ? 'expired 1 day ago' : 'expired $ago days ago';
  }
  return d == 1 ? '1 day left' : '$d days left';
}

HealthStatus? _certStatus(int? days) {
  if (days == null) return null;
  if (days <= 7) return HealthStatus.failed;
  if (days <= webCertExpiringDays) return HealthStatus.warning;
  return null;
}

/// Why Reload is disabled, or null when it may run (spec §6). A lens whose
/// config test could not run (`configOk == null`) may still reload: the probe
/// tests again first.
String? webReloadDisabledReason({
  required Host host,
  required DetectedService service,
  required WebLens lens,
}) {
  if (host.readOnly) return 'Host is read-only.';
  if (webReloadProbeFor(service) == null) return 'Service unit unknown.';
  if (lens.configOk == false) return 'Config test failed.';
  return null;
}

/// The reload probe for [service], or null when its unit or config-test
/// binary is missing or unsafe.
ConfigTestedReloadProbe? webReloadProbeFor(DetectedService service) {
  final unit = service.unit;
  final testBin = safeWebBinary(
    service.binaries,
    webConfigTestBinaryNames(service.id),
  );
  if (!isSafeReloadTarget(id: service.id, unit: unit, testBin: testBin)) {
    return null;
  }
  return ConfigTestedReloadProbe(
    id: service.id,
    unit: unit!,
    testBin: testBin!,
  );
}

/// Error copy for a [ReloadOutcome.failed] result. The host's own output
/// ([ReloadResult.reloadOutput]) is shown apart, in mono.
String webReloadFailedCopy(ReloadResult r) =>
    'Reload failed. ${r.reason ?? ''}'.trim();

/// M7: the web-services sudo hint on a read-only host, where Kelola writes
/// no sudo rules, so no grant is offered.
String webReadOnlySudoBody(String label) =>
    'This host\'s sudo asks for a password, so Kelola could not read the '
    '$label configuration. Kelola never prompts for a sudo password. This '
    'host is read-only in Kelola, so no grant is offered: grants are '
    'unavailable while the host is read-only. Allow writes on the host to '
    'grant read access, or add the exact lines yourself.';

/// Label of the lens read grant action (spec §7b).
const webReadGrantLabel = 'Grant read access for this lens';

/// The `kelola-web` grant for [service] (spec §7b), or null when no line can
/// be granted or host [facts] are not known yet (the install probe needs
/// them). Before the lens has loaded ([lens] null) only the server binary's
/// lines are known; cert and log lines need a lens read for the tool paths,
/// so they come with a second grant.
WebSudoersGrant? webReadGrantFor({
  required Host host,
  required DetectedService service,
  required HostFacts? facts,
  WebLens? lens,
}) {
  if (facts == null) return null;
  final defaults = service.id == ServiceId.apache
      ? apacheDefaultLogs(facts)
      : (
          error: '/var/log/nginx/error.log',
          access: '/var/log/nginx/access.log',
        );
  return WebSudoersGrant.tryCreate(
    user: host.username,
    id: service.id,
    binaries: service.binaries,
    toolPaths: lens?.toolPaths ?? const {},
    // Certificate directives only: never a key path.
    certPaths: lens?.certsByPath.keys.toList() ?? const [],
    errorLog: lens?.errorLogPath ?? defaults.error,
    accessLog: lens?.accessLogPath ?? defaults.access,
    // Files the dump named, checked on the host before the config test is
    // added (includes outside the config root, e.g. /etc/letsencrypt).
    configFiles: lens?.configFiles ?? const [],
  );
}

/// One line saying why [webReadGrantFor] offers nothing.
String webReadGrantBlockedCopy(Host host, DetectedService service) {
  if (webGrantLines(
    user: host.username,
    id: service.id,
    binaries: const {
      'nginx': '/usr/sbin/nginx',
      'apachectl': '/usr/sbin/apachectl',
    },
  ).isEmpty) {
    return 'No grant offered: the login name cannot go in a sudoers rule.';
  }
  final label = descriptorFor(service.id).label;
  return 'No grant offered: the $label binary is not in $_grantDirsCopy.';
}

const _grantDirsCopy = '/usr/bin, /usr/sbin, /bin or /sbin';

/// The read grant a loaded lens offers (spec §7b), and one line for each
/// failing section it cannot cover.
///
/// [grant] is non-null only when it has a line for at least one failing
/// section a grant can fix: the config test refused by sudo, certificates or
/// a log that could not be read. The probe reports a failed read the same
/// whether the file is missing or needs root, so both count. Null [facts]:
/// nothing (no action that could not run).
({WebSudoersGrant? grant, List<String> gaps}) webLensReadGrantOffer({
  required Host host,
  required DetectedService service,
  required HostFacts? facts,
  required WebLens lens,
}) {
  final errors = lens.sectionErrors;
  final config = errors[WebLensSection.configTest] == webConfigTestNoSudo;
  final certs =
      errors.containsKey(WebLensSection.certs) && lens.certsByPath.isNotEmpty;
  final errLog = errors.containsKey(WebLensSection.errorLog);
  final access = errors.containsKey(WebLensSection.access);
  if (facts == null || !(config || certs || errLog || access)) {
    return (grant: null, gaps: const []);
  }
  final grant = webReadGrantFor(
    host: host,
    service: service,
    facts: facts,
    lens: lens,
  );
  final lines = grant?.lines ?? const <String>[];
  bool has(bool Function(String) test) => lines.any(test);
  final coversConfig = config && has((l) => l.endsWith(' -t'));
  final coversCerts = certs && has((l) => l.contains(' x509 '));
  final coversErr = errLog && has((l) => l.contains(' -n 60 '));
  final coversAccess = access && has((l) => l.contains(' -n 2000 '));

  final userOk = webGrantLines(
    user: host.username,
    id: ServiceId.nginx,
    binaries: const {'nginx': '/usr/sbin/nginx'},
  ).isNotEmpty;
  final gaps = <String>[];
  if (!userOk) {
    gaps.add(webReadGrantBlockedCopy(host, service));
  } else {
    if (config && !coversConfig) {
      gaps.add(webReadGrantBlockedCopy(host, service));
    }
    if (certs && !coversCerts) {
      gaps.add(
        isGrantableWebBinary(lens.toolPaths['openssl'], 'openssl')
            ? 'Certificate lines not offered: no certificate path can go in '
                  'a sudoers rule.'
            : 'Certificate lines not offered: openssl is not in '
                  '$_grantDirsCopy.',
      );
    }
    if ((errLog && !coversErr) || (access && !coversAccess)) {
      if (!isGrantableWebBinary(lens.toolPaths['tail'], 'tail')) {
        gaps.add('Log lines not offered: tail is not in $_grantDirsCopy.');
      } else {
        if (errLog && !coversErr) {
          gaps.add(
            'Error log line not offered: its path cannot go in a sudoers '
            'rule.',
          );
        }
        if (access && !coversAccess) {
          gaps.add(
            'Access log line not offered: its path cannot go in a sudoers '
            'rule.',
          );
        }
      }
    }
  }
  final helps = coversConfig || coversCerts || coversErr || coversAccess;
  return (grant: helps ? grant : null, gaps: gaps);
}

/// Whether [user] can go in a sudoers rule: the same rule the lens grants
/// use (fix 2 shows the adm hint only for such a name).
bool webGrantSafeUser(String user) => webGrantLines(
  user: user,
  id: ServiceId.nginx,
  binaries: const {'nginx': '/usr/sbin/nginx'},
).isNotEmpty;

/// Fix 2: copy above the adm command.
const webAdmHintCopy =
    'Add your login to the adm group to read web server logs without sudo:';

/// Fix 2: note under the adm command. Reconnect drops the pooled client,
/// which also closes the host's tunnels, PTY sessions and journal follow.
const webAdmHintNote =
    'Takes effect on the next connection. Reconnect also closes this '
    "host's tunnels, terminal and log follow.";

/// Fix 2: the command the user runs themselves; Kelola never runs it.
String webAdmUsermodCommand(String user) => 'sudo usermod -aG adm $user';

/// Fix 2: the log section that shows the adm hint, or null for none.
///
/// Debian / Ubuntu logs are `www-data:adm 0640` (or `root:adm`), so a login
/// in `adm` reads them without sudo. A section qualifies only when it failed,
/// its log is known to be group `adm` with group read, the login's groups are
/// known and lack `adm`, and [user] is a safe name. Error log first: when
/// both qualify, the hint shows once.
WebLensSection? webAdmHintSection({
  required String user,
  required WebLens lens,
}) {
  final groups = lens.loginGroups;
  if (groups == null || groups.contains('adm')) return null;
  if (!webGrantSafeUser(user)) return null;
  for (final (section, stat) in [
    (WebLensSection.errorLog, lens.errorLogStat),
    (WebLensSection.access, lens.accessLogStat),
  ]) {
    if (!lens.sectionErrors.containsKey(section)) continue;
    if (stat != null && stat.group == 'adm' && stat.groupReadable) {
      return section;
    }
  }
  return null;
}

/// M52 §5d: the web lens (nginx / Apache httpd). One [WebLensProbe] read;
/// pull to refresh re-reads.
class WebLensScreen extends ConsumerStatefulWidget {
  const WebLensScreen({super.key, required this.hostId, required this.service});

  final String hostId;
  final DetectedService service;

  @override
  ConsumerState<WebLensScreen> createState() => _WebLensScreenState();
}

class _WebLensScreenState extends ConsumerState<WebLensScreen> {
  Host? _host;
  HostFacts? _facts;
  WebLens? _lens;
  String? _error;
  bool _busy = true;
  VhostFilter _filter = VhostFilter.all;

  /// Output of the last config test that stopped a reload.
  String? _testFailedOutput;

  /// Host output of the last failed reload, shown in mono under [_error].
  String _reloadOutput = '';

  /// Why the host left out the config test lines of the last read grant
  /// (fix 1), shown with the grant until a grant adds them.
  WebGrantConfigRefusal? _configRefusal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _reloadOutput = '';
    });
    try {
      final repo = ref.read(hostRepositoryProvider);
      final host = _host ?? await repo.get(widget.hostId);
      if (host == null) {
        if (mounted) setState(() => _error = 'Host missing');
        return;
      }
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) return;
      var facts = _facts ?? await repo.facts(host.id);
      if (!mounted) return;
      facts ??= await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const HostFactsProbe(),
      );
      if (!mounted) return;
      // Kept even if the read fails: the sudo hint's grant needs both.
      _host = host;
      _facts = facts;
      final lens = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: WebLensProbe(
          id: widget.service.id,
          binaries: widget.service.binaries,
          unit: widget.service.unit,
        ),
        facts: facts,
      );
      if (!mounted) return;
      setState(() {
        _host = host;
        _facts = facts;
        _lens = lens;
      });
    } catch (e) {
      // SudoRequiredException keeps its hint context in the message, so
      // KelolaError renders the web-services sudo hint (§7b).
      if (mounted) setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload(ConfigTestedReloadProbe probe) async {
    final host = _host;
    if (host == null || _busy) return;
    final allowed = await confirmUnitAction(
      context,
      hostAlias: host.alias,
      unit: probe.unit,
      verb: UnitVerb.reload,
    );
    // Something else (a read, a grant) may have started while it was open.
    if (!allowed || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _reloadOutput = '';
      _testFailedOutput = null;
    });
    var reread = false;
    try {
      final result = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: probe,
        facts: _facts,
      );
      if (!mounted) return;
      switch (result.outcome) {
        case ReloadOutcome.reloaded:
          reread = true;
        case ReloadOutcome.testFailed:
          setState(() => _testFailedOutput = result.testOutput);
        case ReloadOutcome.failed:
          setState(() {
            _error = webReloadFailedCopy(result);
            _reloadOutput = result.reloadOutput;
          });
      }
    } on ReadOnlyViolation {
      if (mounted) setState(() => _error = 'Host is read-only.');
    } catch (e) {
      // SudoRequiredException keeps its hint context (systemd unit grant on
      // the reload leg, web-services on the test leg); KelolaError renders it.
      if (mounted) setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (reread && mounted) await _load();
  }

  String get _title {
    final label = descriptorFor(widget.service.id).label;
    final version = widget.service.version?.trim() ?? '';
    return version.isEmpty ? label : '$label $version';
  }

  @override
  Widget build(BuildContext context) {
    final lens = _lens;
    final now = DateTime.now().toUtc();
    return KelolaPage(
      title: _title,
      busy: _busy,
      bar: KelolaHostAppBar(
        hostAlias: watchedHostAlias(ref, widget.hostId),
        title: _title,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kelolaScrollPadding(context),
          children: [
            if (_error != null) ...[
              _errorView(),
              if (_reloadOutput.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final line in _reloadOutput.split('\n'))
                  Text(
                    line,
                    style: KelolaType.mono(
                      color: context.kc.muted,
                      size: 10.5,
                    ),
                  ),
              ],
              const SizedBox(height: 12),
            ],
            if (lens != null)
              ..._lensBody(context, lens, now)
            else if (_busy)
              const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  /// Sudo failures render as the actionable hint, with the grant that fits
  /// the failure (spec §7):
  /// - a lens read or the reload's config test: the `kelola-web` read grant
  ///   (never Enable Kelola sudo);
  /// - the reload leg on systemd: the PR #17 per-unit grant, through the same
  ///   flow as service detail;
  /// - the reload leg on OpenRC: nothing.
  Widget _errorView() {
    final message = _error!;
    final host = _host;
    final hint = SudoHintContext.tryParse(message);
    if (host != null &&
        host.readOnly &&
        looksLikeSudoRequired(message) &&
        hint.kind == SudoHintKind.webServices) {
      // No grant on a read-only host, so the hint must not point at one.
      final stock = kelolaSudoHint(user: host.username, context: hint);
      return ActionableError(
        title: sudoRequiredTitle,
        body: webReadOnlySudoBody(descriptorFor(widget.service.id).label),
        snippet: [
          for (final l in stock.snippet.split('\n'))
            if (!l.contains('Grant read access')) l,
        ].join('\n'),
      );
    }
    final sudo =
        host != null && !host.readOnly && looksLikeSudoRequired(message);
    // The stock button only for the per-unit grant (same path as service
    // detail). Lens reads never get Enable Kelola sudo.
    final unitGrant = sudo && hint.kind == SudoHintKind.systemd;
    final readGrant =
        sudo &&
        hint.kind == SudoHintKind.webServices &&
        hint.binary != webOpenRcReloadBinary;
    final error = KelolaError(
      message: message,
      sudoUser: host?.username,
      onEnableSudo: unitGrant ? () => _grantUnit(hint) : null,
    );
    final facts = _facts;
    if (!readGrant || facts == null) return error;
    final lens = _lens;
    // A loaded lens offers the same grant in ACTIONS; show it once.
    if (lens != null &&
        webLensReadGrantOffer(
              host: host,
              service: widget.service,
              facts: facts,
              lens: lens,
            ).grant !=
            null) {
      return error;
    }
    final grant = webReadGrantFor(
      host: host,
      service: widget.service,
      facts: facts,
      lens: lens,
    );
    final c = context.kc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        error,
        const SizedBox(height: 8),
        if (grant == null)
          Text(
            webReadGrantBlockedCopy(host, widget.service),
            style: KelolaType.body(color: c.muted, size: 12),
          )
        else
          ServiceRow(
            risk: RiskLevel.mutate,
            name: webReadGrantLabel,
            meta: kelolaWebSudoersPath,
            detail: lens == null
                ? 'Config test and dump; cert and log rules follow once the '
                      'lens loads.'
                : 'Exact read-only sudo rules for this lens.',
            onTap: _busy ? null : () => _grantRead(grant),
          ),
        // With a lens, ACTIONS shows it instead.
        if (lens == null && _configRefusal != null) ...[
          const SizedBox(height: 6),
          _configRefusalNote(context, _configRefusal!),
        ],
      ],
    );
  }

  /// Fix 1: which config path kept the config test out, and why; the path
  /// is host text, in mono.
  Widget _configRefusalNote(BuildContext context, WebGrantConfigRefusal r) =>
      grantNotesText(
        context,
        notes: webGrantNotes(config: r),
        style: KelolaType.body(color: context.kc.muted, size: 12),
      );

  /// PR #17: the reload leg was refused on systemd. The flow offers the one
  /// `systemctl reload <unit>` rule (or Enable on regex-tier hosts, whose
  /// services rule already covers it); then Reload can be tried again.
  Future<void> _grantUnit(SudoHintContext hint) async {
    final host = _host;
    if (host == null || _busy) return;
    final ok = await runEnableKelolaSudoFlow(
      context: context,
      ref: ref,
      host: host,
      facts: _facts,
      hint: hint,
    );
    if (ok && mounted) setState(() => _error = null);
  }

  /// Spec §7b: shows [grant]'s exact lines, installs them, then re-reads.
  Future<void> _grantRead(WebSudoersGrant grant) async {
    final host = _host;
    final facts = _facts;
    if (host == null || facts == null || _busy) return;
    WebGrantConfigRefusal? refused;
    final ok = await runWebGrantFlow(
      context: context,
      ref: ref,
      host: host,
      facts: facts,
      grant: grant,
      certsLater: _lens == null,
      onConfigRefused: (r) => refused = r,
    );
    if ((ok || refused != null) && mounted) {
      setState(() => _configRefusal = refused);
    }
    if (ok && mounted) await _load();
  }

  /// Fix 2: group changes apply to new logins, so drop the pooled client
  /// for this host and read the lens again on a fresh connection. A failed
  /// disconnect is shown as the screen's error (unless the re-read has its
  /// own); the lens is read again either way.
  Future<void> _reconnect() async {
    final host = _host;
    if (host == null || _busy) return;
    setState(() => _busy = true);
    Object? failed;
    try {
      await ref.read(sessionPoolProvider).disconnect(host.id);
    } catch (e) {
      failed = e;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await _load();
    final err = failed;
    if (err != null && mounted && _error == null) {
      setState(() => _error = describeSshError(err));
    }
  }

  /// Fix 2: the adm hint under the log section [section], when it is the
  /// one [webAdmHintSection] picks; else nothing.
  List<Widget> _admHint(
    BuildContext context,
    WebLens l,
    WebLensSection section,
  ) {
    final host = _host;
    if (host == null ||
        webAdmHintSection(user: host.username, lens: l) != section) {
      return const [];
    }
    final c = context.kc;
    final command = webAdmUsermodCommand(host.username);
    return [
      const SizedBox(height: 8),
      Text(webAdmHintCopy, style: KelolaType.body(color: c.muted, size: 12)),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: KelolaType.mono(color: c.text, size: 11),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy, size: 16, color: c.muted),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied')));
            },
          ),
        ],
      ),
      Text(webAdmHintNote, style: KelolaType.body(color: c.dim, size: 11)),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _busy ? null : _reconnect,
          child: Text(
            'Reconnect',
            style: KelolaType.display(color: c.amber, size: 13),
          ),
        ),
      ),
    ];
  }

  List<Widget> _lensBody(BuildContext context, WebLens l, DateTime now) {
    final c = context.kc;
    final findings = l.findings;
    final alarms = bandFindings(findings);
    final facts = [
      for (final f in findings)
        if (f.level == WebFindingLevel.fact) f,
    ];
    final stale = now.difference(l.readAt.toUtc()) > Host.attentionFreshFor;
    return [
      Row(
        children: [
          Text('OVERVIEW', style: _slabStyle(c)),
          const Spacer(),
          Text(
            'read ${Host.ageLabel(l.readAt, now: now)}',
            style: KelolaType.mono(
              color: stale ? c.forHealth(HealthStatus.warning) : c.dim,
              size: 8.5,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _band(c, l, alarms, now),
      for (final s in const [WebLensSection.active, WebLensSection.configTest])
        if (l.sectionErrors[s] != null) _sectionError(c, l.sectionErrors[s]!),
      if (facts.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final f in facts) _factRow(c, f),
      ],
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: StatCard(label: 'Vhosts', value: webVhostsValue(l)),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: StatCard(label: 'Certs', value: webCertsValue(l, now)),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: StatCard(label: '5xx', value: web5xxValue(l)),
          ),
        ],
      ),
      const SizedBox(height: 14),
      ..._vhostSection(context, l, now),
      const SizedBox(height: 14),
      ..._errorLogSection(context, l),
      const SizedBox(height: 14),
      ..._statusSection(c, l, findings),
      ..._bottomRows(context, l),
    ];
  }

  /// Rows at the end of the lens: config-tested Reload (spec §6).
  List<Widget> _bottomRows(BuildContext context, WebLens l) {
    final c = context.kc;
    final host = _host;
    if (host == null) return const [];
    final probe = webReloadProbeFor(widget.service);
    final reason = webReloadDisabledReason(
      host: host,
      service: widget.service,
      lens: l,
    );
    final label = descriptorFor(widget.service.id).label;
    final failed = _testFailedOutput;
    final offer = host.readOnly
        ? null
        : webLensReadGrantOffer(
            host: host,
            service: widget.service,
            facts: _facts,
            lens: l,
          );
    final grant = offer?.grant;
    return [
      const SizedBox(height: 14),
      Text('ACTIONS', style: _slabStyle(c)),
      const SizedBox(height: 8),
      if (grant != null) ...[
        ServiceRow(
          risk: RiskLevel.mutate,
          name: webReadGrantLabel,
          meta: kelolaWebSudoersPath,
          detail: 'Exact read-only sudo rules for the sections that failed.',
          onTap: _busy ? null : () => _grantRead(grant),
        ),
        const SizedBox(height: 6),
      ],
      for (final gap in offer?.gaps ?? const <String>[])
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(gap, style: KelolaType.body(color: c.muted, size: 12)),
        ),
      if (_configRefusal != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _configRefusalNote(context, _configRefusal!),
        ),
      ServiceRow(
        risk: RiskLevel.mutate,
        name: 'Reload $label',
        meta: probe?.unit ?? widget.service.unit ?? 'unit unknown',
        detail: reason ?? 'Tests the config first.',
        onTap: reason == null && probe != null && !_busy
            ? () => _reload(probe)
            : null,
      ),
      if (failed != null) ...[
        const SizedBox(height: 8),
        RiskBand.forHealth(
          status: HealthStatus.failed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Config test failed. Nothing was reloaded.',
                style: KelolaType.display(color: c.text, size: 14),
              ),
              const SizedBox(height: 4),
              for (final line in failed.split('\n'))
                Text(line, style: KelolaType.mono(color: c.muted, size: 10.5)),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _band(
    KelolaColors c,
    WebLens l,
    List<WebFinding> alarms,
    DateTime now,
  ) {
    final worst = alarms.isEmpty ? null : alarms.first;
    return RiskBand.forHealth(
      status: l.overall,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            worst?.message ?? webOkSummary(l, now),
            style: KelolaType.display(color: c.text, size: 14),
          ),
          if (worst?.subject != null) ...[
            const SizedBox(height: 2),
            Text(
              worst!.subject!,
              style: KelolaType.mono(color: c.muted, size: 10.5),
            ),
          ],
          if (l.configOk == false && l.configErrors.length > 1)
            for (final e in l.configErrors.skip(1).take(4))
              Text(e, style: KelolaType.mono(color: c.muted, size: 10)),
          for (final f in alarms.skip(1)) ...[
            const SizedBox(height: 6),
            Text(f.message, style: KelolaType.body(color: c.muted, size: 12)),
            if (f.subject != null)
              Text(
                f.subject!,
                style: KelolaType.mono(color: c.dim, size: 10),
              ),
          ],
        ],
      ),
    );
  }

  /// Facts are plain rows, never alarms.
  Widget _factRow(KelolaColors c, WebFinding f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.message, style: KelolaType.body(color: c.muted, size: 12)),
          if (f.subject != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                f.subject!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KelolaType.mono(color: c.dim, size: 10.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionError(KelolaColors c, String reason) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(reason, style: KelolaType.mono(color: c.muted, size: 10.5)),
    );
  }

  List<Widget> _vhostSection(BuildContext context, WebLens l, DateTime now) {
    final c = context.kc;
    final shown = filterVhosts(l, _filter, now);
    return [
      Text('VHOSTS', style: _slabStyle(c)),
      for (final s in const [WebLensSection.dump, WebLensSection.certs])
        if (l.sectionErrors[s] != null) _sectionError(c, l.sectionErrors[s]!),
      const SizedBox(height: 8),
      Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final f in VhostFilter.values)
            FilterPill(
              label:
                  '${vhostFilterLabel(f)} ${filterVhosts(l, f, now).length}',
              selected: _filter == f,
              onTap: () => setState(() => _filter = f),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (shown.isEmpty)
        KelolaEmpty(body: vhostEmptyCopy(_filter))
      else
        for (final v in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _vhostRow(context, l, v, now),
          ),
    ];
  }

  Widget _vhostRow(BuildContext context, WebLens l, WebVhost v, DateTime now) {
    int? worstDays;
    var unreadable = false;
    for (final p in v.certPaths) {
      final d = l.certsByPath[p]?.daysLeft(now);
      if (d == null) {
        unreadable = true;
      } else if (worstDays == null || d < worstDays) {
        worstDays = d;
      }
    }
    final String detail;
    if (!v.tls) {
      detail = 'no TLS';
    } else if (worstDays != null) {
      detail = 'cert ${_daysLeftCopy(worstDays)}';
    } else if (unreadable) {
      detail = 'certificate unreadable';
    } else {
      detail = 'no certificate';
    }
    return ServiceRow(
      risk: RiskLevel.read,
      status: _certStatus(worstDays),
      name: v.serverNames.isEmpty ? 'Unnamed vhost' : v.serverNames.first,
      meta: v.listen.isEmpty ? v.sourceFile : v.listen.join(' · '),
      detail: detail,
      onTap: () => _showVhost(context, l, v, now),
    );
  }

  Future<void> _showVhost(
    BuildContext context,
    WebLens l,
    WebVhost v,
    DateTime now,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.kc;
        Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(s.toUpperCase(), style: _slabStyle(c)),
        );
        Widget mono(String s) =>
            Text(s, style: KelolaType.mono(color: c.text, size: 11.5));
        Widget body(String s) =>
            Text(s, style: KelolaType.body(color: c.muted, size: 12));
        return KelolaSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KelolaSheetDragHandle(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label('Server names'),
                      if (v.serverNames.isEmpty)
                        body('None set.')
                      else
                        mono(v.serverNames.join(' ')),
                      label('Listen'),
                      if (v.listen.isEmpty)
                        body('None set.')
                      else
                        mono(v.listen.join(' · ')),
                      if (v.root != null) ...[label('Root'), mono(v.root!)],
                      for (final p in v.certPaths) ...[
                        label('Certificate'),
                        if (v.inherited)
                          Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              mono(p),
                              body(webInheritedCertNote(l.id)),
                            ],
                          )
                        else
                          mono(p),
                        ..._certLines(l.certsByPath[p], now, mono, body),
                      ],
                      if (v.tls && v.certPaths.isEmpty) ...[
                        label('Certificate'),
                        body('No certificate in this vhost.'),
                      ],
                      if (v.sourceFile.isNotEmpty) ...[
                        label('Source'),
                        mono(v.sourceFile),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _certLines(
    WebCert? cert,
    DateTime now,
    Widget Function(String) mono,
    Widget Function(String) body,
  ) {
    final end = cert?.notAfter;
    if (cert == null || end == null) {
      return [mono('certificate unreadable')];
    }
    return [
      const SizedBox(height: 4),
      mono(webCertDate(end)),
      body(_daysLeftCopy(cert.daysLeft(now)!)),
      if (cert.sans.isNotEmpty) ...[
        const SizedBox(height: 4),
        mono(cert.sans.join(', ')),
      ],
    ];
  }

  List<Widget> _errorLogSection(BuildContext context, WebLens l) {
    final c = context.kc;
    final err = l.sectionErrors[WebLensSection.errorLog];
    final tail = l.errorLogTail;
    final inline = tail.length > _inlineLogLines
        ? tail.sublist(tail.length - _inlineLogLines)
        : tail;
    return [
      Row(
        children: [
          Text('ERROR LOG', style: _slabStyle(c)),
          const SizedBox(width: 8),
          if (l.errorLogPath != null)
            Expanded(
              child: Text(
                l.errorLogPath!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KelolaType.mono(color: c.dim, size: 8.5),
              ),
            ),
        ],
      ),
      if (err != null) ...[
        _sectionError(c, err),
        ..._admHint(context, l, WebLensSection.errorLog),
      ] else if (tail.isEmpty) ...[
        const SizedBox(height: 6),
        Text(
          'Error log is empty.',
          style: KelolaType.body(color: c.muted, size: 12),
        ),
      ] else ...[
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _showLog(context, l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final line in inline) _logLine(line)],
          ),
        ),
        if (tail.length > inline.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Tap for all ${tail.length} lines.',
              style: KelolaType.body(color: c.dim, size: 11),
            ),
          ),
      ],
    ];
  }

  Widget _logLine(String line) {
    final p = webErrorLogLine(line);
    return JournalLogLine(
      timestamp: p.timestamp,
      message: p.message,
      kind: p.kind,
    );
  }

  Future<void> _showLog(BuildContext context, WebLens l) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.kc;
        return KelolaSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KelolaSheetDragHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  l.errorLogPath ?? 'Error log',
                  style: KelolaType.mono(color: c.muted, size: 11),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final line in l.errorLogTail) _logLine(line)],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _statusSection(
    KelolaColors c,
    WebLens l,
    List<WebFinding> findings,
  ) {
    final err = l.sectionErrors[WebLensSection.access];
    final buckets = <int, int>{2: 0, 3: 0, 4: 0, 5: 0};
    l.statusCounts.forEach((code, n) {
      final b = code ~/ 100;
      if (buckets.containsKey(b)) buckets[b] = buckets[b]! + n;
    });
    final total = buckets.values.fold<int>(0, (a, b) => a + b);
    // Red only when the 5xx finding fires (§5c); otherwise muted.
    final fivexxFires = web5xxFires(findings);
    double frac(int b) => total == 0 ? 0 : buckets[b]! / total;
    return [
      Text('STATUS CODES', style: _slabStyle(c)),
      if (err != null) ...[
        _sectionError(c, err),
        ..._admHint(context, l, WebLensSection.access),
      ] else if (total == 0) ...[
        const SizedBox(height: 6),
        Text(
          'No requests in the access log sample.',
          style: KelolaType.body(color: c.muted, size: 12),
        ),
      ] else ...[
        const SizedBox(height: 8),
        StackedStatMeter(
          segments: [
            StatMeterSegment(fraction: frac(2), tone: StatMeterTone.used),
            StatMeterSegment(fraction: frac(3), tone: StatMeterTone.cached),
            StatMeterSegment(fraction: frac(4), tone: StatMeterTone.accent),
            StatMeterSegment(
              fraction: frac(5),
              tone: fivexxFires ? StatMeterTone.error : StatMeterTone.cached,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          [for (final b in buckets.keys) '${b}xx ${buckets[b]}'].join(' · '),
          style: KelolaType.mono(color: c.muted, size: 10),
        ),
        Text(
          'last $total requests',
          style: KelolaType.body(color: c.dim, size: 11),
        ),
      ],
    ];
  }

  TextStyle _slabStyle(KelolaColors c) =>
      KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9);
}
