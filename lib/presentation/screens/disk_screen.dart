import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart' show KelolaError;
import 'package:kelola/domain/disk/disk_snapshot.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/disk_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
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
  bool _showEphemeral = false;

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
    return KelolaPage(
      title: 'Disk',
      kicker: 'DF THEN DU',
      busy: _loading,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_error != null)
              KelolaError(
                message: _error!,
                sudoUser: _host?.username,
              ),
            if (!_loading && _mounts.isEmpty && _error == null)
              const KelolaEmpty(body: 'No mounts reported by df.'),
            ..._diskTiles(colors),
            if (_du != null) ...[
              const SizedBox(height: 8),
              KelolaSection('du ${_duPath ?? ''}'),
              const SizedBox(height: 8),
              for (final e in _du!)
                KelolaWorkRow(
                  title: e.path,
                  trailing: Text(
                    '${(e.kib / 1024).toStringAsFixed(1)} MiB',
                    style: KelolaFonts.machine(size: 12, color: colors.amber),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _diskTiles(KelolaColors colors) {
    final groups = groupDiskMounts(_mounts);
    return [
      for (final m in groups.primary) _mountCard(colors, m, prominent: true),
      if (groups.ephemeral.isNotEmpty) ...[
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Virtual filesystems',
            style: KelolaFonts.title(size: 14),
          ),
          subtitle: Text(
            '${groups.ephemeral.length} tmpfs / run / dev',
            style: KelolaFonts.machine(color: colors.dim, size: 11),
          ),
          trailing: Icon(
            _showEphemeral
                ? Icons.expand_less_rounded
                : Icons.expand_more_rounded,
            color: colors.muted,
          ),
          onTap: () => setState(() => _showEphemeral = !_showEphemeral),
        ),
        if (_showEphemeral)
          for (final m in groups.ephemeral)
            _mountCard(colors, m, prominent: false),
      ],
    ];
  }

  Widget _mountCard(
    KelolaColors colors,
    DiskMount m, {
    required bool prominent,
  }) {
    final fill = m.usedPercent >= 90
        ? colors.red
        : m.usedPercent >= 80
            ? colors.amber
            : colors.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _duInto(m),
        borderRadius: BorderRadius.circular(12),
        child: RiskBand(
          level: m.usedPercent >= 90
              ? RiskLevel.destructive
              : m.usedPercent >= 80
                  ? RiskLevel.mutate
                  : RiskLevel.read,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${m.mounted}  ${m.usedPercent}%',
                style: KelolaFonts.title(size: prominent ? 16 : 14),
              ),
              const SizedBox(height: 4),
              Text(
                '${m.device} · ${m.fsType} · ${(m.kibUsed / 1024 / 1024).toStringAsFixed(1)} / ${(m.kibTotal / 1024 / 1024).toStringAsFixed(1)} GiB',
                style: KelolaFonts.machine(color: colors.dim, size: 11),
              ),
              if (prominent) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (m.usedPercent / 100).clamp(0, 1),
                    minHeight: 4,
                    color: fill,
                    backgroundColor: colors.surface3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
