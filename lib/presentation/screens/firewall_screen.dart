import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/firewall/firewall_auto_revert.dart';
import 'package:kelola/domain/firewall/firewall_lockout.dart';
import 'package:kelola/domain/firewall/firewall_snapshot.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/firewall_apply_probe.dart';
import 'package:kelola/domain/probes/firewall_list_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_package_action.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class FirewallScreen extends ConsumerStatefulWidget {
  const FirewallScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<FirewallScreen> createState() => _FirewallScreenState();
}

class _FirewallScreenState extends ConsumerState<FirewallScreen> {
  Host? _host;
  HostFacts? _facts;
  FirewallSnapshot? _snap;
  String? _error;
  bool _loading = true;
  final _port = TextEditingController();
  FirewallAutoRevert? _pending;
  FirewallChange? _pendingChange;
  Timer? _tick;
  int _remain = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pending?.dispose();
    _port.dispose();
    super.dispose();
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
      if (resolved.fw == FirewallBackend.none) {
        setState(() {
          _host = host;
          _facts = resolved;
          _snap = const FirewallSnapshot(
            backend: FirewallBackend.none,
            rules: [],
          );
        });
        return;
      }
      final snap = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const FirewallListProbe(),
        facts: resolved,
      );
      setState(() {
        _host = host;
        _facts = resolved;
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

  bool get _mutateOk {
    final host = _host;
    final facts = _facts;
    final snap = _snap;
    if (host == null || facts == null || snap == null) {
      return false;
    }
    if (host.readOnly) {
      return false;
    }
    if (facts.fw == FirewallBackend.iptables ||
        facts.fw == FirewallBackend.none) {
      return false;
    }
    return true;
  }

  Future<void> _mutate(FirewallChange change) async {
    final host = _host;
    final facts = _facts;
    if (host == null || facts == null) {
      return;
    }
    if (_pending != null && _pending!.isPending) {
      setState(() => _error = 'Confirm or wait for the previous firewall change.');
      return;
    }
    final lockout = isFirewallLockoutChange(change, sshPort: host.port);
    final ok = await confirmFirewallChange(
      context,
      hostAlias: host.alias,
      port: change.port,
      lockout: lockout,
      adding: change.verb == FirewallVerb.addPort,
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: FirewallApplyProbe(change),
        facts: facts,
      );
      if (!mounted) {
        return;
      }
      final applied = change.copyWith(
        revertPid: result.revertPid,
        handle: result.handle,
      );
      final controller = FirewallAutoRevert(
        apply: () async {},
        onExpired: () async {
          if (!mounted) {
            return;
          }
          setState(() {
            _pending = null;
            _pendingChange = null;
            _remain = 0;
          });
          await _load();
        },
      );
      _pending = controller;
      _pendingChange = change;
      _remain = FirewallAutoRevert.defaultWindow.inSeconds;
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          if (_remain > 0) {
            _remain--;
          }
        });
      });
      unawaited(controller.start().then((kept) async {
        _tick?.cancel();
        if (!mounted) {
          return;
        }
        if (kept) {
          try {
            await runHostProbe(
              ref: ref,
              context: context,
              host: host,
              probe: FirewallKeepProbe(applied),
              facts: facts,
            );
          } catch (e) {
            setState(() => _error = describeSshError(e));
          }
        }
        setState(() {
          _pending = null;
          _pendingChange = null;
          _remain = 0;
        });
        await _load();
      }));
    } on ReadOnlyViolation {
      setState(() => _error = 'This host is read-only.');
    } catch (e) {
      _tick?.cancel();
      _pending?.dispose();
      setState(() {
        _pending = null;
        _pendingChange = null;
        _error = describeSshError(e);
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _keep() async {
    _pending?.confirm();
  }

  Future<void> _addPort() async {
    final spec = normalizePortSpec(_port.text);
    if (spec.isEmpty || portNumberOf(spec) == null) {
      setState(() => _error = 'Enter a port like 8080 or 8080/tcp.');
      return;
    }
    await _mutate(
      FirewallChange(
        verb: FirewallVerb.addPort,
        port: spec,
        zone: _snap?.defaultZone,
      ),
    );
  }

  String get _kicker {
    final facts = _facts;
    final snap = _snap;
    if (facts == null) {
      return '';
    }
    final name = facts.fw.name.toUpperCase();
    if (facts.fw == FirewallBackend.iptables) {
      return '$name · READ ONLY';
    }
    if (facts.fw == FirewallBackend.none) {
      return 'NONE';
    }
    final n = snap?.rules.length ?? 0;
    return '$name · $n RULES';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final snap = _snap;

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
              'Firewall',
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
              child: _body(c, snap),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(KelolaColors c, FirewallSnapshot? snap) {
    final facts = _facts;
    if (facts != null && facts.fw == FirewallBackend.none) {
      return ListView(
        children: const [
          KelolaEmpty(body: 'No firewall backend discovered.'),
        ],
      );
    }
    final rules = snap?.rules ?? const <FirewallRule>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
      children: [
        if (facts?.fw == FirewallBackend.iptables)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: ServiceRow(
              risk: RiskLevel.read,
              name: 'iptables is read-only',
              meta: 'v1 does not change iptables rules',
            ),
          ),
        if (_pending != null && _pending!.isPending)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ServiceRow(
              risk: RiskLevel.destructive,
              name: 'Host reverts this rule in ${_remain}s',
              meta: _pendingChange == null
                  ? 'timer runs on the server, not this phone'
                  : '${_pendingChange!.port} · keep to cancel the host timer',
              onTap: _keep,
              pillText: 'keep',
            ),
          ),
        if (rules.isEmpty && !_loading)
          const KelolaEmpty(body: 'No firewall rules reported.'),
        for (final rule in rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ServiceRow(
              risk: _ruleRisk(rule),
              name: rule.summary,
              meta: _ruleMeta(rule),
              onTap: _mutateOk && rule.port != null
                  ? () => _mutate(
                        FirewallChange(
                          verb: FirewallVerb.removePort,
                          port: normalizePortSpec(rule.port!),
                          zone: rule.zone ?? snap?.defaultZone,
                          handle: rule.handle,
                          chain: rule.chain,
                        ),
                      )
                  : null,
            ),
          ),
        if (_mutateOk) ...[
          const SectionSlab('Add port'),
          KelolaInput(
            label: 'Port',
            controller: _port,
            hint: '8080/tcp',
            mono: true,
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 10),
          ServiceRow(
            risk: RiskLevel.destructive,
            name: 'Allow port',
            meta: 'destructive · host reverts in 60s unless kept',
            onTap: _addPort,
          ),
        ],
      ],
    );
  }

  RiskLevel _ruleRisk(FirewallRule rule) {
    final host = _host;
    if (host != null && isFirewallLockoutRule(rule, sshPort: host.port)) {
      return RiskLevel.destructive;
    }
    return RiskLevel.read;
  }

  String _ruleMeta(FirewallRule rule) {
    final bits = <String>[
      if (rule.action != null) rule.action!,
      if (rule.zone != null) rule.zone!,
      if (rule.chain != null) rule.chain!,
      if (rule.port != null) rule.port!,
    ];
    return bits.isEmpty ? 'rule' : bits.join(' · ');
  }
}
