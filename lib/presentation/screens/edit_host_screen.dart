import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/ssh/openssh_user_cert.dart';
import 'package:kelola/presentation/host_env/env_bindings_sheet.dart';
import 'package:kelola/presentation/widgets/confirm_host_action.dart';
import 'package:kelola/providers.dart';

class EditHostScreen extends ConsumerStatefulWidget {
  const EditHostScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<EditHostScreen> createState() => _EditHostScreenState();
}

class _EditHostScreenState extends ConsumerState<EditHostScreen> {
  final _alias = TextEditingController();
  final _address = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _tags = TextEditingController();
  final _sshCert = TextEditingController();
  Host? _host;
  List<Host> _others = const [];
  String? _jumpHostId;
  bool _readOnly = false;
  bool _agentForward = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _alias.dispose();
    _address.dispose();
    _port.dispose();
    _user.dispose();
    _tags.dispose();
    _sshCert.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(hostRepositoryProvider);
    final host = await repo.get(widget.hostId);
    final all = await repo.list();
    if (!mounted) {
      return;
    }
    setState(() {
      _host = host;
      _others = all.where((h) => h.id != widget.hostId).toList();
      _alias.text = host?.alias ?? '';
      _address.text = host?.address ?? '';
      _port.text = '${host?.port ?? 22}';
      _user.text = host?.username ?? '';
      _tags.text = host?.tags.join(', ') ?? '';
      _sshCert.text = host?.sshCertificate ?? '';
      _jumpHostId = host?.jumpHostId;
      _readOnly = host?.readOnly ?? false;
      _agentForward = host?.agentForward ?? false;
      _loading = false;
    });
  }

  Future<void> _saveAlias([String? value]) async {
    final host = _host;
    if (host == null) {
      return;
    }
    final next = (value ?? _alias.text).trim();
    if (next.isEmpty || next == host.alias) {
      return;
    }
    await ref.read(hostRepositoryProvider).updateHost(host.id, alias: next);
    final updated = await ref.read(hostRepositoryProvider).get(host.id);
    if (!mounted) {
      return;
    }
    setState(() => _host = updated ?? host);
    ref.invalidate(hostsProvider);
  }

  Future<void> _toggleReadOnly() async {
    final host = _host;
    if (host == null) {
      return;
    }
    final turningOn = !_readOnly;
    final ok = await showMutateConfirm(
      context,
      title: turningOn
          ? 'Make ${host.alias} read-only?'
          : 'Allow writes on ${host.alias}?',
      body: turningOn
          ? 'Reboot, Flush caches, and other changes will be blocked until you turn this off.'
          : 'Reboot, Flush caches, and other mutate actions will run again.',
      confirmLabel: turningOn ? 'Read-only' : 'Allow writes',
    );
    if (!ok || !mounted) {
      return;
    }
    await ref.read(hostRepositoryProvider).setReadOnly(host.id, turningOn);
    final updated = await ref.read(hostRepositoryProvider).get(host.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _host = updated ?? host;
      _readOnly = turningOn;
    });
    ref.invalidate(hostsProvider);
  }

  Future<void> _toggleAgentForward() async {
    final host = _host;
    if (host == null) {
      return;
    }
    final turningOn = !_agentForward;
    if (turningOn) {
      final ok = await showMutateConfirm(
        context,
        title: 'Forward agent on ${host.alias}?',
        body: 'This host may ask Kelola to sign with the on-device key. '
            'The private key never leaves the phone. sshd must allow agent forwarding.',
        confirmLabel: 'Forward agent',
      );
      if (!ok || !mounted) {
        return;
      }
    }
    await ref.read(hostRepositoryProvider).setAgentForward(host.id, turningOn);
    await ref.read(sessionPoolProvider).disconnect(host.id);
    final updated = await ref.read(hostRepositoryProvider).get(host.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _host = updated ?? host;
      _agentForward = turningOn;
    });
    ref.invalidate(hostsProvider);
  }

  Future<void> _saveIdentity() async {
    final host = _host;
    if (host == null) {
      return;
    }
    await _saveAlias();
    final certRaw = _sshCert.text.trim();
    if (certRaw.isNotEmpty) {
      try {
        final cert = parseOpenSshUserCert(certRaw);
        final blob = ref.read(enrollmentProvider).publicBlob;
        if (blob == null ||
            !cert.matchesPublicBlob(blob) ||
            !cert.isValidAt(DateTime.now().toUtc())) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Certificate does not match this device key.'),
            ),
          );
          return;
        }
      } on FormatException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        return;
      }
    }
    final certChanged = certRaw != (host.sshCertificate ?? '');
    await ref.read(hostRepositoryProvider).setSshCertificate(
          host.id,
          certRaw.isEmpty ? null : certRaw,
        );
    if (certChanged) {
      await ref.read(sessionPoolProvider).disconnect(host.id);
    }
    await ref.read(hostRepositoryProvider).setHostTags(
          host.id,
          _tags.text.split(RegExp(r'[,;\s]+')),
        );

    final address = _address.text.trim();
    final user = _user.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (address.isEmpty || user.isEmpty) {
      return;
    }
    if (user == 'root') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kelola does not log in as root. Use a sudoer.'),
        ),
      );
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Port must be 1-65535.')),
      );
      return;
    }

    final addressChanged = address != host.address;
    final userChanged = user != host.username;
    final portChanged = port != host.port;
    final jumpChanged = _jumpHostId != host.jumpHostId;
    if (!addressChanged && !userChanged && !portChanged && !jumpChanged) {
      final updated = await ref.read(hostRepositoryProvider).get(host.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _host = updated ?? host;
        _tags.text = (updated ?? host).tags.join(', ');
      });
      ref.invalidate(hostsProvider);
      Navigator.of(context).pop();
      return;
    }

    if (addressChanged || userChanged) {
      final alias = (await ref.read(hostRepositoryProvider).get(host.id))
              ?.alias ??
          host.alias;
      final ok = await confirmHostAction(
        context,
        hostAlias: alias,
        title: addressChanged ? 'Change address?' : 'Change username?',
        body: addressChanged
            ? userChanged
                ? 'The pinned host key will be cleared and Trust on First Use will run for the new address. The new user may not have Kelola\'s key in authorized_keys.'
                : 'The pinned host key for this host will be cleared. Next connect runs Trust on First Use for the new address.'
            : 'This user\'s authorized_keys may not include Kelola\'s key. Next connect uses the new username. The host key pin stays (same machine).',
        confirmLabel: 'Change',
        risk: RiskLevel.destructive,
        warning: addressChanged
            ? 'Never reuse the old pin for a new address. That is a security hole.'
            : 'If authorized_keys is missing Kelola\'s key, SSH will fail until you add it.',
      );
      if (!ok || !mounted) {
        return;
      }
    }

    final result = await ref.read(hostRepositoryProvider).updateHost(
          host.id,
          address: addressChanged ? address : null,
          username: userChanged ? user : null,
          port: portChanged ? port : null,
          jumpHostId: jumpChanged ? _jumpHostId : null,
          clearJumpHost: jumpChanged && _jumpHostId == null,
        );
    if (result.disconnectSession) {
      await ref.read(sessionPoolProvider).disconnect(host.id);
    }
    final updated = await ref.read(hostRepositoryProvider).get(host.id);
    if (!mounted) {
      return;
    }
    setState(() => _host = updated ?? host);
    ref.invalidate(hostsProvider);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final host = _host;
    return KelolaWashScaffold(
      appBar: KelolaHostAppBar(
        hostAlias: host?.alias ?? watchedHostAlias(ref, widget.hostId),
        title: 'Edit host',
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.amber))
          : host == null
              ? Center(
                  child: Text(
                    'Host missing',
                    style: KelolaType.body(color: c.red, size: 13),
                  ),
                )
              : ListView(
                  padding: kelolaScrollPadding(context, top: 8),
                  children: [
                    KelolaInput(
                      key: const Key('edit-host-alias'),
                      label: 'Alias',
                      controller: _alias,
                      hint: host.alias,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _saveAlias,
                    ),
                    const SizedBox(height: 14),
                    KelolaInput(
                      key: const Key('edit-host-address'),
                      label: 'Address',
                      controller: _address,
                      hint: host.address,
                      mono: true,
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: KelolaInput(
                            key: const Key('edit-host-port'),
                            label: 'Port',
                            controller: _port,
                            mono: true,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: KelolaInput(
                            key: const Key('edit-host-username'),
                            label: 'Username',
                            controller: _user,
                            hint: host.username,
                            mono: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    KelolaInput(
                      key: const Key('edit-host-tags'),
                      label: 'Tags',
                      controller: _tags,
                      hint: 'prod, staging, homelab',
                    ),
                    const SizedBox(height: 16),
                    HostEnvSection(host: host),
                    const SizedBox(height: 16),
                    KelolaInput(
                      key: const Key('edit-host-ssh-cert'),
                      label: 'SSH certificate',
                      controller: _sshCert,
                      hint: 'ecdsa-sha2-nistp256-cert-v01@openssh.com ...',
                      mono: true,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Jump host',
                      style: KelolaType.body(color: c.muted, size: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        FilterPill(
                          label: 'None',
                          selected: _jumpHostId == null,
                          onTap: () => setState(() => _jumpHostId = null),
                        ),
                        for (final other in _others)
                          FilterPill(
                            label: other.alias,
                            selected: _jumpHostId == other.id,
                            onTap: () =>
                                setState(() => _jumpHostId = other.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          'Read-only',
                          style: KelolaType.body(color: c.muted, size: 12),
                        ),
                        const Spacer(),
                        ModePill(
                          label: 'Read-only',
                          active: _readOnly,
                          onTap: _toggleReadOnly,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          'Agent forward',
                          style: KelolaType.body(color: c.muted, size: 12),
                        ),
                        const Spacer(),
                        ModePill(
                          label: 'Agent forward',
                          active: _agentForward,
                          onTap: _toggleAgentForward,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _saveIdentity,
                      style: FilledButton.styleFrom(backgroundColor: c.amber),
                      child: Text(
                        'Save',
                        style: KelolaType.display(color: c.ink, size: 13),
                      ),
                    ),
                  ],
                ),
    );
  }
}
