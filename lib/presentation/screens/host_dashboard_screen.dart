import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/host_key_mismatch_screen.dart';
import 'package:kelola/presentation/screens/units_screen.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/risk_band.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/providers.dart';

class HostDashboardScreen extends ConsumerStatefulWidget {
  const HostDashboardScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<HostDashboardScreen> createState() =>
      _HostDashboardScreenState();
}

class _HostDashboardScreenState extends ConsumerState<HostDashboardScreen> {
  Host? _host;
  HostFacts? _facts;
  DashboardSnapshot? _dash;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(hostRepositoryProvider);
      final host = await repo.get(widget.hostId);
      if (host == null) {
        setState(() => _error = 'Host missing');
        return;
      }
      _host = host;
      _facts = await repo.facts(host.id);
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final sw = Stopwatch()..start();
      final facts = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const HostFactsProbe(),
      );
      await repo.saveFacts(host.id, facts);
      if (!mounted) {
        return;
      }
      final dash = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const DashboardProbe(),
        facts: facts,
      );
      sw.stop();
      final attention = switch (dash.attention) {
        HostAttentionFromSnapshot.failedUnits => HostAttention.failedUnits,
        HostAttentionFromSnapshot.diskHigh => HostAttention.diskHigh,
        HostAttentionFromSnapshot.healthy => HostAttention.healthy,
      };
      await repo.updateAttention(
        id: host.id,
        attention: attention,
        lastSeenAt: DateTime.now().toUtc(),
        rttMs: sw.elapsedMilliseconds,
      );
      final updated = await repo.get(host.id);
      setState(() {
        _facts = facts;
        _dash = dash;
        _host = updated ?? host;
      });
    } on HostKeyMismatchException catch (e) {
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HostKeyMismatchScreen(
            hostAlias: _host?.alias ?? widget.hostId,
            pinned: e.pinnedFingerprint,
            seen: e.seenFingerprint,
          ),
        ),
      );
    } catch (e) {
      await ref.read(hostRepositoryProvider).updateAttention(
            id: widget.hostId,
            attention: HostAttention.unreachable,
          );
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final host = _host;
    final dash = _dash;
    final facts = _facts;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(host?.alias ?? 'Host'),
            Text(
              [
                if (facts != null) facts.label,
                if (dash != null) 'up ${_formatUp(dash.uptime)}',
                if (host?.lastRttMs != null) '${host!.lastRttMs}ms',
              ].join(' · ').toUpperCase(),
              style: TextStyle(color: colors.dim, fontSize: 11),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: colors.red)),
              ),
            if (host?.note != null && host!.note!.isNotEmpty) ...[
              RiskBand(
                level: RiskLevel.read,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Note', style: TextStyle(color: colors.dim, fontSize: 11)),
                    Text(host.note!),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (dash != null && dash.failedUnitCount > 0) ...[
              InkWell(
                onTap: () => _openUnits(failedOnly: true),
                borderRadius: BorderRadius.circular(10),
                child: RiskBand(
                  level: RiskLevel.destructive,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${dash.failedUnitCount} units failed'),
                      Text(
                        dash.failedUnitNames.join(' · '),
                        style: TextStyle(color: colors.red, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (dash != null)
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  _stat(colors, 'Load 1m', dash.load1.toStringAsFixed(2)),
                  _stat(colors, 'Memory', '${dash.memUsedPercent}%'),
                  _stat(colors, 'Disk /', '${dash.diskRootPercent}%'),
                  _stat(
                    colors,
                    'Failed',
                    '${dash.failedUnitCount}',
                    onTap: () => _openUnits(failedOnly: true),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: colors.line),
              ),
              title: const Text('Services'),
              subtitle: Text(
                'Failed units first',
                style: TextStyle(color: colors.dim, fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right, color: colors.dim),
              onTap: () => _openUnits(
                failedOnly: dash == null || dash.failedUnitCount > 0,
              ),
            ),
            if (facts != null) ...[
              const SizedBox(height: 16),
              Text(
                '${facts.init.name} · ${facts.pkg.name} · ${facts.fw.name} · ${facts.arch}',
                style: TextStyle(color: colors.dim, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openUnits({required bool failedOnly}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnitsScreen(
          hostId: widget.hostId,
          failedOnly: failedOnly,
        ),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Widget _stat(
    KelolaColors colors,
    String k,
    String v, {
    VoidCallback? onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k.toUpperCase(), style: TextStyle(color: colors.dim, fontSize: 10)),
          const SizedBox(height: 4),
          Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        ],
      ),
    );
    if (onTap == null) {
      return child;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: child,
    );
  }

  static String _formatUp(Duration d) {
    final days = d.inDays;
    if (days > 0) {
      return '${days}d';
    }
    return '${d.inHours}h';
  }
}
