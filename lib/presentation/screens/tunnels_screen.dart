import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_presets.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:kelola/domain/tunnels/tunnel_validation.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

typedef TunnelLaunchUrl = Future<bool> Function(Uri url);

enum _ActiveFilter { all, thisHost, failed }

/// Formats idle-close countdown from [closesAtUtc] relative to [now].
String tunnelIdleCountdownLabel(DateTime closesAtUtc, DateTime now) {
  final secs = closesAtUtc.toUtc().difference(now.toUtc()).inSeconds;
  final remaining = secs < 0 ? 0 : secs;
  final m = remaining ~/ 60;
  final s = remaining % 60;
  return 'closing in $m:${s.toString().padLeft(2, '0')}';
}

/// Formats tunnel uptime from [openedAtUtc] relative to [now].
String tunnelUptimeLabel(DateTime openedAtUtc, DateTime now) {
  final secs = now.toUtc().difference(openedAtUtc.toUtc()).inSeconds;
  final elapsed = secs < 0 ? 0 : secs;
  if (elapsed < 60) return '${elapsed}s';
  final m = elapsed ~/ 60;
  final s = elapsed % 60;
  if (m < 60) return '${m}m ${s.toString().padLeft(2, '0')}s';
  final h = m ~/ 60;
  final rm = m % 60;
  return '${h}h ${rm}m';
}

Future<void> showTunnelsLockedExplainer(BuildContext context) {
  final c = context.kc;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) {
      return KelolaSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tunnels',
                style: KelolaType.display(color: c.text, size: 18),
              ),
              const SizedBox(height: 10),
              Text(
                'Tunnels open a local SSH port forward so you can reach '
                'admin UIs on this host from your phone browser. '
                'This build keeps tunnels locked.',
                style: KelolaType.body(color: c.muted, size: 13),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<bool> showTunnelTargetEditor(
  BuildContext context, {
  required String hostId,
  TunnelTarget? existing,
  Future<void> Function(TunnelTarget target)? onSave,
  Future<void> Function(String id)? onDelete,
}) async {
  final c = context.kc;
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) {
      return KelolaSheet(
        child: _TunnelTargetEditor(
          hostId: hostId,
          existing: existing,
          onSave: onSave,
          onDelete: onDelete,
        ),
      );
    },
  );
  return result == true;
}

class _TunnelTargetEditor extends StatefulWidget {
  const _TunnelTargetEditor({
    required this.hostId,
    this.existing,
    this.onSave,
    this.onDelete,
  });

  final String hostId;
  final TunnelTarget? existing;
  final Future<void> Function(TunnelTarget target)? onSave;
  final Future<void> Function(String id)? onDelete;

  @override
  State<_TunnelTargetEditor> createState() => _TunnelTargetEditorState();
}

class _TunnelTargetEditorState extends State<_TunnelTargetEditor> {
  late TunnelPreset _preset;
  late final TextEditingController _label;
  late final TextEditingController _remoteHost;
  late final TextEditingController _remotePort;
  late final TextEditingController _path;
  late TunnelScheme _scheme;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _preset = existing == null ? TunnelPreset.cockpit : TunnelPreset.custom;
    _label = TextEditingController(text: existing?.label ?? 'Cockpit');
    _remoteHost =
        TextEditingController(text: existing?.remoteHost ?? '127.0.0.1');
    _remotePort = TextEditingController(
      text: (existing?.remotePort ?? 9090).toString(),
    );
    _path = TextEditingController(text: existing?.path ?? '/');
    _scheme = existing?.scheme ?? TunnelScheme.https;
    if (existing == null) {
      final applied = TunnelPresets.apply(
        preset: TunnelPreset.cockpit,
        id: 'draft',
        hostId: widget.hostId,
      );
      _label.text = applied.label;
      _remotePort.text = applied.remotePort.toString();
      _scheme = applied.scheme;
      _path.text = applied.path;
      _remoteHost.text = '127.0.0.1';
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _remoteHost.dispose();
    _remotePort.dispose();
    _path.dispose();
    super.dispose();
  }

  void _applyPreset(TunnelPreset preset) {
    final applied = TunnelPresets.apply(
      preset: preset,
      id: widget.existing?.id ?? 'draft',
      hostId: widget.hostId,
      label: _label.text,
      remoteHost: _remoteHost.text,
      remotePort: int.tryParse(_remotePort.text.trim()) ?? 0,
      scheme: _scheme,
      path: _path.text,
    );
    setState(() {
      _preset = preset;
      _error = null;
      if (preset != TunnelPreset.custom) {
        _label.text = applied.label;
        _remotePort.text = applied.remotePort.toString();
        _scheme = applied.scheme;
        _path.text = applied.path;
        if (_remoteHost.text.trim().isEmpty) {
          _remoteHost.text = '127.0.0.1';
        }
      }
    });
  }

  TunnelTarget _draft() {
    return TunnelTarget(
      id: widget.existing?.id ?? const Uuid().v7(),
      hostId: widget.hostId,
      label: _label.text.trim(),
      remoteHost: _remoteHost.text.trim(),
      remotePort: int.tryParse(_remotePort.text.trim()) ?? 0,
      scheme: _scheme,
      path: _path.text.trim().isEmpty ? '/' : _path.text.trim(),
    );
  }

  Future<void> _save() async {
    final target = _draft();
    final result = validateTunnelTarget(target);
    if (!result.isOk) {
      setState(() => _error = result.error);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final save = widget.onSave;
      if (save != null) {
        await save(target);
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    final del = widget.onDelete;
    if (id == null || del == null) return;
    setState(() => _saving = true);
    try {
      await del(id);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        18,
        16,
        8 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              editing ? 'Edit target' : 'Add target',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final preset in TunnelPreset.values)
                  FilterPill(
                    label: preset.name,
                    selected: _preset == preset,
                    onTap: _saving ? null : () => _applyPreset(preset),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: KelolaType.body(color: c.red, size: 13),
              ),
            ],
            const SizedBox(height: 12),
            ServiceRow(
              risk: RiskLevel.read,
              name: editing ? 'Save' : 'Add target',
              meta: 'saved for this host',
              onTap: _saving ? null : _save,
            ),
            if (editing && widget.onDelete != null) ...[
              const SizedBox(height: 8),
              ServiceRow(
                risk: RiskLevel.destructive,
                name: 'Delete target',
                meta: 'removes saved target only',
                onTap: _saving ? null : _delete,
              ),
            ],
            const SizedBox(height: 12),
            KelolaInput(
              label: 'Label',
              controller: _label,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 10),
            KelolaInput(
              label: 'Remote host',
              controller: _remoteHost,
              mono: true,
              hint: '127.0.0.1',
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 10),
            KelolaInput(
              label: 'Remote port',
              controller: _remotePort,
              mono: true,
              keyboardType: TextInputType.number,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 10),
            KelolaInput(
              label: 'Path',
              controller: _path,
              mono: true,
              hint: '/',
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 10),
            Text('Scheme', style: KelolaType.body(color: c.muted, size: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              children: [
                for (final scheme in TunnelScheme.values)
                  FilterPill(
                    label: scheme.value,
                    selected: _scheme == scheme,
                    onTap: _saving
                        ? null
                        : () => setState(() {
                              _scheme = scheme;
                              _preset = TunnelPreset.custom;
                              _error = null;
                            }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TunnelsScreen extends ConsumerStatefulWidget {
  const TunnelsScreen({
    super.key,
    required this.hostId,
    this.clock,
    this.launchUrlFn,
    this.initialNotificationsAllowed,
  });

  final String hostId;
  final DateTime Function()? clock;
  final TunnelLaunchUrl? launchUrlFn;
  final bool? initialNotificationsAllowed;

  @override
  ConsumerState<TunnelsScreen> createState() => _TunnelsScreenState();
}

class _TunnelsScreenState extends ConsumerState<TunnelsScreen> {
  _ActiveFilter _filter = _ActiveFilter.all;
  bool _askedNotifications = false;
  bool? _notificationsAllowed;
  Timer? _tick;
  String? _hostAlias;
  bool _starting = false;

  DateTime get _now =>
      (widget.clock ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    _notificationsAllowed = widget.initialNotificationsAllowed;
    if (widget.clock == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    _loadAlias();
  }

  Future<void> _loadAlias() async {
    final host = await ref.read(hostRepositoryProvider).get(widget.hostId);
    if (!mounted || host == null) return;
    setState(() => _hostAlias = host.alias);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _ensureNotifications() async {
    if (_askedNotifications) return;
    _askedNotifications = true;
    final ok =
        await ref.read(tunnelBridgeProvider).requestPostNotifications();
    if (!mounted) return;
    setState(() => _notificationsAllowed = ok);
  }

  Future<void> _startTarget(TunnelTarget target) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await _ensureNotifications();
      final alias = _hostAlias ??
          (await ref.read(hostRepositoryProvider).get(widget.hostId))?.alias ??
          widget.hostId;
      await ref.read(tunnelManagerProvider).open(
            target,
            hostAlias: alias,
          );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopTunnel(ActiveTunnel tunnel) async {
    final ok = await showMutateConfirm(
      context,
      title: 'Stop ${tunnel.target.label}?',
      body:
          'Closes the local forward on 127.0.0.1:${tunnel.localPort}. '
          'The remote service keeps running.',
      confirmLabel: 'Stop tunnel',
    );
    if (!ok || !mounted) return;
    await ref.read(tunnelManagerProvider).close(tunnel.id);
  }

  Future<void> _openEditor({TunnelTarget? existing}) async {
    final repo = ref.read(tunnelRepositoryProvider);
    await showTunnelTargetEditor(
      context,
      hostId: widget.hostId,
      existing: existing,
      onSave: repo.upsert,
      onDelete: existing == null ? null : repo.delete,
    );
  }

  Future<void> _openInBrowser(ActiveTunnel tunnel) async {
    final uri = tunnel.url;
    final c = context.kc;
    final isHttp = tunnel.target.scheme == TunnelScheme.http;
    final body = isHttp
        ? 'Traffic between the browser and the loopback listener is '
            'plaintext on this device. The SSH hop to the host is encrypted; '
            'the listener binds only to 127.0.0.1 for that reason.'
        : "Your browser will warn that the certificate doesn't match "
            '127.0.0.1. That\'s expected — the tunnel itself is encrypted by SSH.';

    final proceed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KelolaRadii.lg),
        ),
        side: BorderSide(color: c.line),
      ),
      builder: (ctx) {
        return KelolaSheet(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHttp ? 'HTTP tunnel' : 'HTTPS tunnel',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 10),
                Text(body, style: KelolaType.body(color: c.muted, size: 13)),
                const SizedBox(height: 8),
                Text(
                  uri.toString(),
                  style: KelolaType.mono(color: c.text, size: 11),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (proceed != true || !mounted) return;

    final launch = widget.launchUrlFn ??
        ((u) => launchUrl(u, mode: LaunchMode.externalApplication));
    await launch(uri);
  }

  List<ActiveTunnel> _filtered(List<ActiveTunnel> all) {
    switch (_filter) {
      case _ActiveFilter.all:
        return all;
      case _ActiveFilter.thisHost:
        return all.where((t) => t.target.hostId == widget.hostId).toList();
      case _ActiveFilter.failed:
        return all.where((t) => t.state == TunnelState.failed).toList();
    }
  }

  String _emptyCopy() {
    switch (_filter) {
      case _ActiveFilter.all:
      case _ActiveFilter.thisHost:
        return 'No active tunnels.';
      case _ActiveFilter.failed:
        return 'No failed tunnels.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final targetsAsync = ref.watch(tunnelTargetsProvider(widget.hostId));
    final activeAsync = ref.watch(activeTunnelsProvider);
    final targets = targetsAsync.valueOrNull ?? const <TunnelTarget>[];
    final active = activeAsync.valueOrNull ?? const <ActiveTunnel>[];
    final thisHostCount =
        active.where((t) => t.target.hostId == widget.hostId).length;
    final failedCount =
        active.where((t) => t.state == TunnelState.failed).length;
    final filtered = _filtered(active);
    final showNotifExplainer = _notificationsAllowed == false;

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
              'Tunnels',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            Text(
              (_hostAlias ?? widget.hostId).toUpperCase(),
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _openEditor(),
            child: const Text('Add'),
          ),
        ],
      ),
      body: ListView(
        padding: kelolaScrollPadding(context),
        children: [
          if (showNotifExplainer) ...[
            RiskBand(
              risk: RiskLevel.read,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Notifications are off — the tunnel still runs, but you '
                      'won\'t see the ongoing status.',
                      style: KelolaType.body(color: c.muted, size: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(tunnelBridgeProvider).openNotificationSettings();
                    },
                    child: const Text('Open settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SectionSlab('Saved targets'),
          if (targets.isEmpty)
            const KelolaEmpty(body: 'No saved targets for this host.')
          else
            for (final t in targets) ...[
              RiskBand(
                risk: RiskLevel.read,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.label,
                            style: KelolaType.display(color: c.text, size: 13),
                          ),
                          Text(
                            '${t.scheme.value}://${t.remoteHost}:${t.remotePort}${t.path}',
                            style: KelolaType.mono(color: c.muted, size: 11),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openEditor(existing: t),
                      child: const Text('Edit'),
                    ),
                    TextButton(
                      onPressed: _starting ? null : () => _startTarget(t),
                      child: const Text('Start'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
          const SizedBox(height: 10),
          const SectionSlab('Active'),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              FilterPill(
                label: 'All ${active.length}',
                selected: _filter == _ActiveFilter.all,
                onTap: () => setState(() => _filter = _ActiveFilter.all),
              ),
              FilterPill(
                label: 'This host $thisHostCount',
                selected: _filter == _ActiveFilter.thisHost,
                onTap: () => setState(() => _filter = _ActiveFilter.thisHost),
              ),
              FilterPill(
                label: 'Failed $failedCount',
                selected: _filter == _ActiveFilter.failed,
                onTap: () => setState(() => _filter = _ActiveFilter.failed),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            KelolaEmpty(body: _emptyCopy())
          else
            for (final tunnel in filtered) ...[
              _ActiveTunnelCard(
                tunnel: tunnel,
                now: _now,
                onStop: () => _stopTunnel(tunnel),
                onOpen: () => _openInBrowser(tunnel),
                onRetry: () =>
                    ref.read(tunnelManagerProvider).retry(tunnel.id),
                onDismiss: () =>
                    ref.read(tunnelManagerProvider).dismissFailed(tunnel.id),
              ),
              const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }
}

class _ActiveTunnelCard extends StatelessWidget {
  const _ActiveTunnelCard({
    required this.tunnel,
    required this.now,
    required this.onStop,
    required this.onOpen,
    required this.onRetry,
    required this.onDismiss,
  });

  final ActiveTunnel tunnel;
  final DateTime now;
  final VoidCallback onStop;
  final VoidCallback onOpen;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final failed = tunnel.state == TunnelState.failed;
    final listening = tunnel.state == TunnelState.listening ||
        tunnel.state == TunnelState.idleClosing ||
        tunnel.state == TunnelState.starting;
    final metaParts = <String>[
      tunnel.hostAlias,
      if (tunnel.localPort > 0) '127.0.0.1:${tunnel.localPort}',
      '${tunnel.openChannels} ch',
      if (!failed) 'up ${tunnelUptimeLabel(tunnel.openedAtUtc, now)}',
    ];
    if (tunnel.state == TunnelState.idleClosing && tunnel.closesAtUtc != null) {
      metaParts.add(tunnelIdleCountdownLabel(tunnel.closesAtUtc!, now));
    }
    if (failed && tunnel.errorSummary != null) {
      metaParts.add(tunnel.errorSummary!);
    }

    return RiskBand(
      risk: failed ? RiskLevel.destructive : RiskLevel.read,
      status: failed ? HealthStatus.failed : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tunnel.target.label,
            style: KelolaType.display(color: c.text, size: 13),
          ),
          const SizedBox(height: 2),
          Text(
            metaParts.join(' · '),
            style: KelolaType.mono(color: c.muted, size: 11),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (listening && tunnel.localPort > 0)
                TextButton(
                  onPressed: onOpen,
                  child: const Text('Open'),
                ),
              if (listening)
                TextButton(
                  onPressed: onStop,
                  child: const Text('Stop'),
                ),
              if (failed) ...[
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('Dismiss'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
