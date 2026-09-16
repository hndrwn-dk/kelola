import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart'
    hide RiskBand;
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/disk/disk_snapshot.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/metrics/rate_sample.dart';
import 'package:kelola/domain/probes/disk_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/rate_probes.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
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
  String? _rateError;
  bool _loading = true;
  bool _measuring = false;
  bool _showEphemeral = false;
  List<DiskIoRate> _rates = const [];

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

  Future<void> _sampleRates(Host host) async {
    setState(() {
      _measuring = true;
      _rateError = null;
      _rates = const [];
    });
    try {
      final first = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const DiskstatsProbe(),
        facts: _facts,
      );
      if (!mounted) {
        return;
      }
      final sw = Stopwatch()..start();
      await Future<void>.delayed(kRateSampleInterval);
      if (!mounted) {
        return;
      }
      final second = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const DiskstatsProbe(),
        facts: _facts,
      );
      sw.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _rates = DiskIoRates.between(first, second, sw.elapsed);
        _rateError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _rates = const [];
          _rateError =
              'Could not finish disk rate sample. ${describeSshError(e)}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _measuring = false);
      }
    }
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
      await _sampleRates(host);
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
    final mounts = _mounts.length;
    return KelolaPage(
      title: 'Disk',
      bar: KelolaHostAppBar(
        hostAlias: watchedHostAlias(ref, widget.hostId),
        title: 'Disk',
        contextLine: mounts == 0 ? null : '$mounts filesystems',
      ),
      busy: _loading || _measuring,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: kelolaScrollPadding(
            context,
            left: 16,
            top: 8,
            right: 16,
          ),
          children: [
            if (_error != null)
              KelolaError(
                message: _error!,
                sudoUser: _host?.username,
              ),
            _rateSection(colors),
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

  Widget _rateSection(KelolaColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DISK ACTIVITY',
            style: KelolaType.mono(
              color: colors.dim,
              size: 8.5,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 8),
          if (_measuring)
            Text(
              'Measuring ${kRateSampleInterval.inSeconds}s sample…',
              style: KelolaType.body(color: colors.muted, size: 13),
            )
          else if (_rateError != null)
            KelolaError(message: _rateError!, sudoUser: _host?.username)
          else if (_rates.isEmpty)
            Text(
              'No whole-disk counters in /proc/diskstats.',
              style: KelolaType.body(color: colors.muted, size: 13),
            )
          else
            for (final r in _rates) ...[
              ServiceRow(
                risk: RiskLevel.read,
                name: r.name,
                meta:
                    'r ${formatRateBytes(r.readBytesPerSec)} · w ${formatRateBytes(r.writeBytesPerSec)}',
                endValue: '${r.busyPercent.round()}%',
                endMeta: 'busy',
              ),
              Padding(
                padding: const EdgeInsets.only(left: 14, bottom: 8),
                child: Text(
                  'IOPS r ${formatRateIops(r.readIops)} · w ${formatRateIops(r.writeIops)}',
                  style: KelolaType.mono(color: colors.dim, size: 11),
                ),
              ),
            ],
        ],
      ),
    );
  }

  List<Widget> _diskTiles(KelolaColors colors) {
    final groups = groupDiskMounts(_mounts);
    return [
      for (final m in groups.primary) _mountCard(colors, m, prominent: true),
      if (groups.ephemeral.isNotEmpty) ...[
        const SizedBox(height: 8),
        ServiceRow(
          risk: RiskLevel.read,
          name: 'Virtual filesystems',
          meta: '${groups.ephemeral.length} tmpfs / run / dev',
          endValue: _showEphemeral ? 'Hide' : 'Show',
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
