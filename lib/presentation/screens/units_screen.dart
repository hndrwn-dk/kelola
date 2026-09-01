import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/unit_list_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/unit_detail_screen.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
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
  bool _failedOnly = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _failedOnly = widget.failedOnly;
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
      });
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
    final result = _result;
    final visible = _visible(result);

    return Scaffold(
      appBar: AppBar(
        title: Text(_host?.alias ?? 'Services'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Filter units',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Failed'),
                      selected: _failedOnly,
                      onSelected: (_) => setState(() => _failedOnly = true),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('All'),
                      selected: !_failedOnly,
                      onSelected: (_) => setState(() => _failedOnly = false),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_error!, style: TextStyle(color: colors.red)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _body(colors, result, visible),
            ),
          ),
        ],
      ),
    );
  }

  List<ServiceUnit> _visible(UnitListResult? result) {
    if (result == null) {
      return const [];
    }
    var list = _failedOnly ? result.failed : result.units;
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (u) =>
                u.name.toLowerCase().contains(q) ||
                u.description.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  Widget _body(
    KelolaColors colors,
    UnitListResult? result,
    List<ServiceUnit> visible,
  ) {
    if (result != null && !result.initSupported) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'This host is not systemd or OpenRC. Use a shell for services.',
              style: TextStyle(color: colors.muted),
            ),
          ),
        ],
      );
    }
    if (!_loading && result != null && visible.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _failedOnly
                  ? 'No failed units. Switch to All to browse services.'
                  : 'No units match.',
              style: TextStyle(color: colors.muted),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final unit = visible[i];
        final color = unit.isFailed
            ? colors.red
            : unit.isActive
                ? colors.green
                : colors.dim;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            tileColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colors.line),
            ),
            title: Text(unit.name, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              [
                unit.active,
                unit.sub,
                if (unit.unitFileState != null) unit.unitFileState!,
                if (unit.description.isNotEmpty) unit.description,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.dim, fontSize: 12),
            ),
            trailing: Text(
              unit.active,
              style: TextStyle(color: color, fontSize: 11),
            ),
            onTap: () async {
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
            },
          ),
        );
      },
    );
  }
}
