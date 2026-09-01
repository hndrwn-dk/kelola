import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/disk/disk_snapshot.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/disk_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/risk_band.dart';
import 'package:kelola/providers.dart';

class DiskScreen extends ConsumerStatefulWidget {
  const DiskScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<DiskScreen> createState() => _DiskScreenState();
}

class _DiskScreenState extends ConsumerState<DiskScreen> {
  Host? _host;
  HostFacts? _facts;
  List<DiskMount> _mounts = const [];
  List<DuEntry>? _du;
  String? _duPath;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _ensure(Host host) async {
    await ref.read(enrollmentProvider.notifier).ensureKey();
    var facts = await ref.read(hostRepositoryProvider).facts(host.id);
    if (facts == null) {
      if (!mounted) {
        return;
      }
      facts = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const HostFactsProbe(),
      );
    }
    _facts = facts;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final host = await ref.read(hostRepositoryProvider).get(widget.hostId);
      if (host == null) {
        setState(() => _error = 'Host missing');
        return;
      }
      await _ensure(host);
      if (!mounted) {
        return;
      }
      final mounts = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const DiskProbe(),
        facts: _facts,
      );
      setState(() {
        _host = host;
        _mounts = mounts;
      });
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _duInto(DiskMount mount) async {
    final host = _host;
    if (host == null) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _duPath = mount.mounted;
    });
    try {
      final du = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: DuProbe(mount.mounted),
        facts: _facts,
      );
      setState(() => _du = du);
    } catch (e) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Disk')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: TextStyle(color: colors.red)),
            for (final m in _mounts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _duInto(m),
                  child: RiskBand(
                    level: m.usedPercent >= 90
                        ? RiskLevel.destructive
                        : m.usedPercent >= 80
                            ? RiskLevel.mutate
                            : RiskLevel.read,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m.mounted}  ${m.usedPercent}%'),
                        Text(
                          '${m.device} · ${m.fsType} · ${(m.kibUsed / 1024 / 1024).toStringAsFixed(1)} / ${(m.kibTotal / 1024 / 1024).toStringAsFixed(1)} GiB',
                          style: TextStyle(color: colors.dim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_du != null) ...[
              const SizedBox(height: 8),
              Text(
                'du ${_duPath ?? ''}',
                style: TextStyle(color: colors.dim, fontSize: 11),
              ),
              const SizedBox(height: 6),
              for (final e in _du!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${(e.kib / 1024).toStringAsFixed(1)} MiB  ${e.path}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
