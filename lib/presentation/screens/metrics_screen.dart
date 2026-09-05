import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/processes/process_list_view.dart';
import 'package:kelola/domain/hosts/poll_backoff.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/metrics_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/providers.dart';

enum MetricsFocus { cpu, memory }

class MetricsScreen extends ConsumerStatefulWidget {
  const MetricsScreen({
    super.key,
    required this.hostId,
    this.focus = MetricsFocus.cpu,
  });

  final String hostId;
  final MetricsFocus focus;

  @override
  ConsumerState<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends ConsumerState<MetricsScreen> {
  final _cpu = <double>[];
  final _mem = <double>[];
  MetricsSnapshot? _snap;
  HostFacts? _facts;
  String? _error;
  bool _loading = true;
  Duration? _poll = const Duration(seconds: 5);
  Timer? _timer;
  late MetricsFocus _focus;
  final _backoff = PollBackoff();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focus;
    _tick();
  }

  void _arm() {
    _timer?.cancel();
    if (_poll == null || _backoff.stopped) {
      return;
    }
    _timer = Timer(_poll!, _tick);
  }

  void _setPoll(Duration? poll) {
    setState(() {
      _poll = poll;
      if (poll != null) {
        _backoff.success();
      }
    });
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      final host = await ref.read(hostRepositoryProvider).get(widget.hostId);
      if (host == null) {
        setState(() => _error = 'Host missing');
        return;
      }
      await ref.read(enrollmentProvider.notifier).ensureKey();
      var facts = await ref.read(hostRepositoryProvider).facts(host.id);
      if (!mounted) {
        return;
      }
      facts ??= await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const HostFactsProbe(),
      );
      if (!mounted) {
        return;
      }
      final snap = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const MetricsProbe(),
        facts: facts,
      );
      _backoff.success();
      setState(() {
        _snap = snap;
        _facts = facts;
        _error = null;
        _loading = false;
        _cpu.add(snap.cpuPercent);
        _mem.add(snap.memUsedPercent.toDouble());
        if (_cpu.length > 40) {
          _cpu.removeAt(0);
        }
        if (_mem.length > 40) {
          _mem.removeAt(0);
        }
      });
      _scheduleNext(_poll ?? const Duration(seconds: 5));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeSshError(e);
          _loading = false;
        });
      }
      final delay = _backoff.failure();
      if (delay != null) {
        _scheduleNext(delay);
      } else if (mounted) {
        setState(() {});
      }
    } finally {
      _busy = false;
    }
  }

  void _scheduleNext(Duration delay) {
    _timer?.cancel();
    if (_poll == null || _backoff.stopped) {
      return;
    }
    _timer = Timer(delay, _tick);
  }

  String get _kicker {
    return metricsPollKicker(
      poll: _poll,
      disconnected: _backoff.disconnected,
    );
  }

  HealthStatus _pctHealth(int percent) {
    if (percent >= 90) return HealthStatus.failed;
    if (percent >= 75) return HealthStatus.warning;
    return HealthStatus.healthy;
  }

  List<double> _spark(List<double> percents) {
    return [for (final v in percents) (v / 100).clamp(0.0, 1.0)];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final snap = _snap;
    final cpuFocus = _focus == MetricsFocus.cpu;
    final procs = snap == null
        ? const <MetricsProc>[]
        : (cpuFocus ? snap.topCpu : snap.topMem);
    final cores = _facts?.nprocCores;

    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Metrics', style: KelolaType.display(color: c.text, size: 16)),
            Text(
              _kicker,
              style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_loading)
            LinearProgressIndicator(
              minHeight: 1.5,
              backgroundColor: c.surface,
              color: c.amber,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                FilterPill(
                  label: '2s',
                  selected: _poll?.inSeconds == 2,
                  onTap: () => _setPoll(const Duration(seconds: 2)),
                ),
                FilterPill(
                  label: '5s',
                  selected: _poll?.inSeconds == 5,
                  onTap: () => _setPoll(const Duration(seconds: 5)),
                ),
                FilterPill(
                  label: '30s',
                  selected: _poll?.inSeconds == 30,
                  onTap: () => _setPoll(const Duration(seconds: 30)),
                ),
                FilterPill(
                  label: 'pause',
                  selected: _poll == null,
                  onTap: () => _setPoll(null),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _tick,
              child: ListView(
                padding: kelolaScrollPadding(context, top: 12),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: KelolaError(message: _error!),
                    ),
                  if (snap != null) ...[
                    _metricCard(
                      c: c,
                      label: 'CPU',
                      value: '${snap.cpuPercent.toStringAsFixed(0)}%',
                      meta: cores == null ? 'this screen' : '$cores cores',
                      values: _spark(_cpu),
                      color: c.amber,
                    ),
                    const SizedBox(height: 8),
                    _metricCard(
                      c: c,
                      label: 'Memory',
                      value: '${snap.memUsedPercent}%',
                      meta: 'used',
                      values: _spark(_mem),
                      color: c.forHealth(_pctHealth(snap.memUsedPercent)),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 5,
                      children: [
                        FilterPill(
                          label: 'CPU',
                          selected: cpuFocus,
                          onTap: () => setState(() => _focus = MetricsFocus.cpu),
                        ),
                        FilterPill(
                          label: 'Memory',
                          selected: !cpuFocus,
                          onTap: () =>
                              setState(() => _focus = MetricsFocus.memory),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      cpuFocus ? 'TOP CPU' : 'TOP MEMORY',
                      style: KelolaType.mono(
                        color: c.dim,
                        size: 8.5,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final p in procs) ...[
                      ServiceRow(
                        risk: RiskLevel.read,
                        status: p.cpu >= 100
                            ? HealthStatus.warning
                            : HealthStatus.unknown,
                        name: p.command,
                        meta: 'pid ${p.pid} · ${p.user}',
                        endValue: cpuFocus
                            ? formatProcessCpu(p.cpu)
                            : formatProcessRss(p.rssKb),
                        endMeta: cpuFocus ? 'cpu' : 'rss',
                      ),
                      const SizedBox(height: 6),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Samples stay on this screen. No 5m/1h/24h history yet.',
                      style: KelolaType.body(color: c.dim, size: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required KelolaColors c,
    required String label,
    required String value,
    required String meta,
    required List<double> values,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(KelolaRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: KelolaType.mono(
                        color: c.dim,
                        size: 8.5,
                        letterSpacing: 0.9,
                      ),
                    ),
                    Text(
                      value,
                      style: KelolaType.display(color: c.text, size: 18),
                    ),
                  ],
                ),
              ),
              Text(meta, style: KelolaType.mono(color: c.muted, size: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Sparkline(values: values, color: color),
        ],
      ),
    );
  }
}
