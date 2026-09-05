import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/network/network_snapshot.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/network_list_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class NetworkScreen extends ConsumerStatefulWidget {
  const NetworkScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends ConsumerState<NetworkScreen> {
  Host? _host;
  NetworkSnapshot _snap = const NetworkSnapshot();
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      await ref.read(enrollmentProvider.notifier).ensureKey();
      var facts = await repo.facts(host.id);
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
        probe: const NetworkListProbe(),
        facts: facts,
      );
      setState(() {
        _host = host;
        _snap = snap;
      });
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String get _kicker {
    final n = _snap.interfaces.length;
    final p = _snap.ports.length;
    return '$n IFACES · $p PORTS · READ';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Network', style: KelolaType.display(color: c.text, size: 16)),
            Text(
              _kicker,
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
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
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _body(KelolaColors c) {
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: KelolaError(
              message: _error!,
              sudoUser: _host?.username,
            ),
          ),
        ],
      );
    }
    final empty = _snap.interfaces.isEmpty &&
        _snap.routes.isEmpty &&
        _snap.ports.isEmpty;
    if (empty && !_loading) {
      return const KelolaEmpty(
        title: 'No network data',
        body: 'ip and ss returned nothing this user can read.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: kelolaScrollPadding(context),
        children: [
          _heading(c, 'INTERFACES'),
          const SizedBox(height: 8),
          if (_snap.interfaces.isEmpty)
            Text(
              'No interfaces (loopback omitted).',
              style: KelolaType.body(color: c.muted, size: 13),
            ),
          for (final iface in _snap.interfaces) ...[
            ServiceRow(
              risk: RiskLevel.read,
              status: iface.isUp ? HealthStatus.healthy : HealthStatus.failed,
              name: iface.name,
              meta: iface.addresses.isEmpty
                  ? iface.operstate
                  : iface.addresses.join('  '),
              pillText: iface.operstate,
              pillStatus:
                  iface.isUp ? HealthStatus.healthy : HealthStatus.failed,
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 10),
          _heading(c, 'ROUTES'),
          const SizedBox(height: 8),
          if (_snap.routes.isEmpty)
            Text(
              'No routes.',
              style: KelolaType.body(color: c.muted, size: 13),
            ),
          for (final r in _snap.routes) ...[
            ServiceRow(
              risk: RiskLevel.read,
              name: r.dst,
              meta: r.meta.isEmpty ? r.dev ?? '' : r.meta,
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 10),
          _heading(c, 'LISTENING'),
          const SizedBox(height: 8),
          if (_snap.ports.isEmpty)
            Text(
              'No listening ports.',
              style: KelolaType.body(color: c.muted, size: 13),
            ),
          for (final p in _snap.ports) ...[
            ServiceRow(
              risk: RiskLevel.read,
              kicker: p.proto.toUpperCase(),
              name: p.local,
              meta: p.process.isEmpty
                  ? p.proto
                  : p.pid == null
                      ? p.process
                      : '${p.process} · ${p.pid}',
              endValue: p.state,
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _heading(KelolaColors c, String label) {
    return Text(
      label,
      style: KelolaType.mono(
        color: c.dim,
        size: 8.5,
        letterSpacing: 0.9,
      ),
    );
  }
}
