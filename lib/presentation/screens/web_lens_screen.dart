import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';
import 'package:kelola/domain/services/web_lens.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

/// Certs at or under this many days left count as expiring (spec §5c).
const webCertExpiringDays = 21;

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

/// Certs stat: `<k> expiring`, `ok`, or `unknown` when the certs section
/// failed or TLS vhosts have no readable certificate.
String webCertsValue(WebLens l, DateTime now) {
  var expiring = 0;
  var readable = 0;
  for (final c in l.certsByPath.values) {
    final d = c.daysLeft(now);
    if (d == null) continue;
    readable++;
    if (d <= webCertExpiringDays) expiring++;
  }
  if (expiring > 0) return '$expiring expiring';
  if (l.sectionErrors.containsKey(WebLensSection.certs)) return 'unknown';
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

/// Band copy when nothing failed or warns.
String webOkSummary(WebLens l, DateTime now) {
  final config = l.configOk == null ? 'Config not tested' : 'Config OK';
  final vhosts = webVhostsValue(l);
  final vhostsText = vhosts == 'unknown'
      ? 'vhosts unknown'
      : (l.vhosts.length == 1 ? '1 vhost' : '$vhosts vhosts');
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
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

  /// Sudo failures render as the actionable hint. Task 10 attaches the
  /// "Grant read access" action here.
  Widget _errorView() {
    return KelolaError(
      message: _error!,
      sudoUser: _host?.username,
    );
  }

  List<Widget> _lensBody(BuildContext context, WebLens l, DateTime now) {
    final c = context.kc;
    final findings = l.findings;
    final alarms = [
      for (final f in findings)
        if (f.level != WebFindingLevel.fact) f,
    ];
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
      // Task 9 appends the Reload row here.
      ..._bottomRows(context, l),
    ];
  }

  /// Rows at the end of the lens (Task 9: config-tested Reload).
  List<Widget> _bottomRows(BuildContext context, WebLens l) => const [];

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
      if (err != null)
        _sectionError(c, err)
      else if (tail.isEmpty) ...[
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
    final fivexxFires = findings.any(
      (f) => f.level != WebFindingLevel.fact && f.message.startsWith('5xx '),
    );
    double frac(int b) => total == 0 ? 0 : buckets[b]! / total;
    return [
      Text('STATUS CODES', style: _slabStyle(c)),
      if (err != null)
        _sectionError(c, err)
      else if (total == 0) ...[
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
