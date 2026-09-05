import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/package_apply_probe.dart';
import 'package:kelola/domain/probes/package_list_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_package_action.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class PackagesScreen extends ConsumerStatefulWidget {
  const PackagesScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends ConsumerState<PackagesScreen> {
  Host? _host;
  HostFacts? _facts;
  PackageSnapshot? _snap;
  PackageListFilter _filter = PackageListFilter.all;
  bool _landed = false;
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
      final resolved = facts;
      if (resolved == null) {
        return;
      }
      if (resolved.pkg == PackageManager.unknown) {
        setState(() {
          _host = host;
          _facts = resolved;
          _snap = PackageSnapshot(
            manager: resolved.pkg,
            updates: const [],
            rebootRequired: false,
          );
        });
        return;
      }
      final snap = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const PackageListProbe(),
        facts: resolved,
      );
      setState(() {
        _host = host;
        _facts = resolved;
        _snap = snap;
        if (!_landed) {
          _filter = defaultPackageFilter(snap);
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

  Future<void> _apply() async {
    final host = _host;
    final facts = _facts;
    final snap = _snap;
    if (host == null || facts == null || snap == null) {
      return;
    }
    final visible = visiblePackageUpdates(snap, _filter);
    if (visible.isEmpty) {
      return;
    }
    final securityOnly = _filter == PackageListFilter.security;
    final ok = await confirmPackageApply(
      context,
      hostAlias: host.alias,
      names: visible.map((u) => u.name).toList(),
      securityOnly: securityOnly,
      rebootRequired: snap.rebootRequired,
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: PackageApplyProbe(
          names: visible.map((u) => u.name).toList(),
          securityOnly: securityOnly,
          manager: facts.pkg,
        ),
        facts: facts,
      );
      await _load();
    } on ReadOnlyViolation {
      setState(() => _error = 'This host is read-only.');
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String get _kicker {
    final snap = _snap;
    final facts = _facts;
    if (snap == null || facts == null) {
      return '';
    }
    final mgr = facts.pkg.name.toUpperCase();
    if (facts.pkg == PackageManager.unknown) {
      return 'NO MANAGER';
    }
    return '$mgr · ${snap.updates.length} UPDATES';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final snap = _snap;
    final counts = snap == null
        ? const PackageListCounts(security: 0, all: 0)
        : PackageListCounts.from(snap);
    final visible =
        snap == null ? const <PackageUpdate>[] : visiblePackageUpdates(snap, _filter);
    final securityOn = snap?.securitySupported ?? false;

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
              'Packages',
              style: KelolaType.display(color: c.text, size: 16),
            ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final filter in PackageListFilter.values)
                  FilterPill(
                    label: packageListChipLabel(filter, counts),
                    selected: _filter == filter,
                    enabled: filter != PackageListFilter.security || securityOn,
                    onTap: () => setState(() => _filter = filter),
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
              child: _body(snap, visible),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    PackageSnapshot? snap,
    List<PackageUpdate> visible,
  ) {
    final facts = _facts;
    if (facts != null && facts.pkg == PackageManager.unknown) {
      return ListView(
        children: const [
          KelolaEmpty(body: 'No package manager discovered.'),
        ],
      );
    }
    if (!_loading && snap != null && visible.isEmpty) {
      return ListView(
        children: [
          KelolaEmpty(body: packageListEmptyCopy(_filter)),
        ],
      );
    }
    return ListView(
      padding: kelolaScrollPadding(context),
      children: [
        if (snap != null && snap.rebootRequired)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ServiceRow(
              risk: RiskLevel.destructive,
              name: 'Reboot required',
              meta: snap.rebootReasons.isEmpty
                  ? '/var/run/reboot-required or needs-restarting'
                  : snap.rebootReasons.take(6).join(' · '),
            ),
          ),
        if (snap != null &&
            snap.securityCount > 0 &&
            _filter != PackageListFilter.security)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ServiceRow(
              risk: RiskLevel.destructive,
              name: '${snap.securityCount} security updates',
              meta: securityPreview(snap),
            ),
          ),
        for (final u in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ServiceRow(
              risk: u.security ? RiskLevel.mutate : RiskLevel.read,
              name: u.name,
              meta: u.versionMeta,
              pillText: u.security ? 'sec' : null,
            ),
          ),
        if (visible.isNotEmpty && _host?.readOnly != true) ...[
          const SizedBox(height: 8),
          ServiceRow(
            risk: RiskLevel.destructive,
            name: applyLabel(visible.length, _filter),
            meta: snap != null && snap.rebootRequired
                ? 'destructive · may require reboot'
                : 'destructive · never auto-applied',
            onTap: _apply,
          ),
        ],
      ],
    );
  }
}

String securityPreview(PackageSnapshot snap) {
  final names = snap.updates.where((u) => u.security).map((u) => u.name).toList();
  if (names.length <= 3) {
    return names.join(' · ');
  }
  return '${names.take(3).join(' · ')} · +${names.length - 3}';
}

String applyLabel(int count, PackageListFilter filter) {
  if (filter == PackageListFilter.security) {
    return 'Apply $count security updates';
  }
  return 'Apply $count updates';
}
