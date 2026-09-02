import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/audit/audit_event.dart';
import 'package:kelola/domain/audit/audit_view.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/providers.dart';

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key, this.hostId});

  final String? hostId;

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  List<AuditEvent> _rows = const [];
  bool _showAll = false;
  String? _hostId;

  @override
  void initState() {
    super.initState();
    _hostId = widget.hostId;
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(hostRepositoryProvider).listAudit(
          hostId: _hostId,
        );
    if (mounted) {
      setState(() => _rows = rows);
    }
  }

  Future<void> _copyJson() async {
    await Clipboard.setData(ClipboardData(text: encodeAuditExport(_rows)));
  }

  Future<void> _selectHost(String? hostId) async {
    setState(() => _hostId = hostId);
    await _load();
  }

  String? _scopeLabel(List<Host> hosts) {
    final id = _hostId;
    if (id == null) {
      return null;
    }
    for (final h in hosts) {
      if (h.id == id) {
        return h.alias;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final now = DateTime.now().toUtc();
    final hosts = List<Host>.of(ref.watch(hostsProvider).valueOrNull ?? [])
      ..sort((a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()));
    final summary = formatAuditWeekSummary(summarizeAudit(_rows, now: now));
    final visible = filterAudit(_rows, showAll: _showAll);
    final groups = groupAuditByDay(visible, now: now);
    final title = auditScreenTitle(_scopeLabel(hosts));

    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: KelolaType.display(color: c.text, size: 16)),
            Text(
              _rows.isEmpty ? 'LOCAL TRAIL' : '${_rows.length} RECORDS',
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Copy JSON',
            onPressed: _rows.isEmpty ? null : _copyJson,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            if (hosts.isNotEmpty && widget.hostId == null) ...[
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  FilterPill(
                    label: 'All hosts',
                    selected: _hostId == null,
                    onTap: () => _selectHost(null),
                  ),
                  for (final host in hosts)
                    FilterPill(
                      label: host.alias,
                      selected: _hostId == host.id,
                      onTap: () => _selectHost(host.id),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (_rows.isNotEmpty) ...[
              Text(
                summary,
                style: KelolaType.body(color: c.muted, size: 13),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilterPill(
                  label: 'Show all activity',
                  selected: _showAll,
                  onTap: () => setState(() => _showAll = !_showAll),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_rows.isEmpty)
              _Empty(
                title: 'Quiet',
                body: 'No commands recorded yet. Actions over SSH appear here.',
              )
            else if (visible.isEmpty)
              const _Empty(
                title: 'No changes',
                body:
                    'Read probes are hidden. Show all activity to see polls and inspections.',
              )
            else
              for (final group in groups) ...[
                Text(
                  group.label,
                  style: KelolaType.mono(
                    color: c.dim,
                    size: 8.5,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 8),
                for (final e in group.events) ...[
                  _AuditRow(
                    event: e,
                    onTap: () => _openDetail(context, e),
                  ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, AuditEvent e) {
    final c = context.kc;
    final failed = auditFailed(e);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KelolaRadii.lg),
        ),
        side: BorderSide(color: c.line),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                auditDisplayTitle(e),
                style: KelolaType.display(color: c.text, size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _metaLine(e),
                style: KelolaType.mono(
                  color: failed ? c.red : c.muted,
                  size: 11,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                e.command,
                style: KelolaType.mono(color: c.text, size: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.event, required this.onTap});

  final AuditEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final failed = auditFailed(event);
    final health = failed
        ? HealthStatus.failed
        : (event.orphan ? HealthStatus.warning : null);
    return ServiceRow(
      risk: auditRisk(event.risk),
      status: health,
      name: auditDisplayTitle(event),
      meta: _metaLine(event),
      pillText: failed ? 'failed' : (event.orphan ? 'interrupted' : null),
      pillStatus: health,
      endValue: _clock(event.timestampUtc),
      onTap: onTap,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 28, 14, 8),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: KelolaType.display(color: c.text, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: KelolaType.body(color: c.muted, size: 14),
          ),
        ],
      ),
    );
  }
}

String _metaLine(AuditEvent e) {
  return [
    e.hostAlias,
    e.risk,
    if (e.usedSudo) 'sudo',
    if (e.orphan) 'interrupted',
    if (e.exitCode != null) 'exit ${e.exitCode}',
    _duration(e.durationMs),
    if (e.errorSummary != null) e.errorSummary!,
  ].join(' · ');
}

String _duration(int ms) {
  if (ms >= 1000) {
    final s = ms / 1000;
    return s >= 10 ? '${s.round()}s' : '${s.toStringAsFixed(1)}s';
  }
  return '${ms}ms';
}

String _clock(DateTime utc) {
  final l = utc.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
