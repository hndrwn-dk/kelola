import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/unit_list_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/domain/units/unit_list_view.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/unit_detail_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class UnitsScreen extends ConsumerStatefulWidget {
  const UnitsScreen({
    super.key,
    required this.hostId,
    this.failedOnly = true,
  });

  final String hostId;
  final bool failedOnly;

  @override
  ConsumerState<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends ConsumerState<UnitsScreen> {
  Host? _host;
  HostFacts? _facts;
  UnitListResult? _result;
  String? _error;
  bool _loading = true;
  late UnitListFilter _filter;
  String _q = '';
  bool _searching = false;
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    _filter = widget.failedOnly ? UnitListFilter.failed : UnitListFilter.all;
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
      var facts = await repo.facts(host.id) ?? HostFacts.undiscovered;
      if (facts.init == InitSystem.unknown) {
        if (!mounted) {
          return;
        }
        facts = await runHostProbe(
          ref: ref,
          context: context,
          host: host,
          probe: const HostFactsProbe(),
        );
        await repo.saveFacts(host.id, facts);
      }
      if (!mounted) {
        return;
      }
      final result = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const UnitListProbe(),
        facts: facts,
      );
      setState(() {
        _host = host;
        _facts = facts;
        _result = result;
        if (!_landed) {
          _filter = defaultUnitListFilter(result.units);
          _landed = true;
        }
      });
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  UnitListView get _view {
    final units = _result?.units ?? const <ServiceUnit>[];
    return UnitListView.build(units, _filter, query: _q);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final result = _result;
    final counts = UnitListCounts.from(result?.units ?? const <ServiceUnit>[]);
    final kicker = result == null ? null : unitListKicker(counts);

    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Services',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            if (kicker != null)
              Text(
                kicker,
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
            tooltip: 'Filter units',
            icon: Icon(
              _searching ? Icons.search_off_rounded : Icons.search_rounded,
            ),
            onPressed: () => setState(() => _searching = !_searching),
          ),
        ],
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_searching) ...[
                  TextField(
                    autofocus: true,
                    style: KelolaType.mono(color: c.text, size: 13),
                    decoration: InputDecoration(
                      hintText: 'Filter units',
                      hintStyle: KelolaType.mono(color: c.dim, size: 13),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final filter in UnitListFilter.values)
                      FilterPill(
                        label: unitListChipLabel(filter, counts),
                        selected: _filter == filter,
                        onTap: () => setState(() => _filter = filter),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: KelolaError(
                message: _error!,
                sudoUser: _host?.username,
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _body(c, result, _view),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(KelolaColors c, UnitListResult? result, UnitListView view) {
    if (result != null && !result.initSupported) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Text(
                  'Not systemd',
                  textAlign: TextAlign.center,
                  style: KelolaType.display(color: c.text, size: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'This host is not systemd or OpenRC. Use a shell for services.',
                  textAlign: TextAlign.center,
                  style: KelolaType.body(color: c.muted, size: 14),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (!_loading && result != null && view.isEmpty) {
      return ListView(
        children: [
          KelolaEmpty(body: _emptyCopy(result)),
        ],
      );
    }
    return ListView(
      padding: kelolaScrollPadding(context),
      children: [
        for (final unit in view.failed) _row(unit),
        if (view.showRunningSlab) _slab(c, 'Running'),
        for (final unit in view.running) _row(unit),
        if (view.showOtherSlab) _slab(c, 'Inactive'),
        for (final unit in view.other) _row(unit),
      ],
    );
  }

  String _emptyCopy(UnitListResult result) {
    final counts = UnitListCounts.from(result.units);
    return unitListEmptyCopy(
      _filter,
      activeCount: counts.running,
      query: _q,
    );
  }

  Widget _slab(KelolaColors c, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 3),
      child: Text(
        label.toUpperCase(),
        style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
      ),
    );
  }

  Widget _row(ServiceUnit unit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ServiceRow(
        risk: RiskLevel.read,
        status: _health(unit),
        name: unit.name,
        meta: unitListMeta(unit),
        onTap: () => _open(unit),
      ),
    );
  }

  HealthStatus _health(ServiceUnit unit) {
    if (unit.isFailed) {
      return HealthStatus.failed;
    }
    if (unit.isActive) {
      return HealthStatus.healthy;
    }
    return HealthStatus.unknown;
  }

  Future<void> _open(ServiceUnit unit) async {
    final host = _host;
    final facts = _facts;
    if (host == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnitDetailScreen(
          host: host,
          facts: facts ?? HostFacts.undiscovered,
          unitName: unit.name,
        ),
      ),
    );
    await _load();
  }
}
