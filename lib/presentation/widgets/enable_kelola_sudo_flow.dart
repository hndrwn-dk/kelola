import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/sudoers_install_probe.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/providers.dart';

String kelolaSudoersGroupLabel(KelolaSudoersGroup g) {
  return switch (g) {
    KelolaSudoersGroup.packages => 'Packages',
    KelolaSudoersGroup.firewall => 'Firewall',
    KelolaSudoersGroup.hostPower => 'Host power',
  };
}

/// Guided install of [kelolaSudoersPath]. Returns true on verified install.
Future<bool> runEnableKelolaSudoFlow({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  HostFacts? facts,
  Set<KelolaSudoersGroup>? preselected,
}) async {
  await ref.read(enrollmentProvider.notifier).ensureKey();
  var resolved = facts ?? await ref.read(hostRepositoryProvider).facts(host.id);
  if (resolved == null && context.mounted) {
    resolved = await runHostProbe(
      ref: ref,
      context: context,
      host: host,
      probe: const HostFactsProbe(),
    );
  }
  if (resolved == null || !context.mounted) {
    return false;
  }

  var fileExists = false;
  try {
    fileExists = await runHostProbe(
      ref: ref,
      context: context,
      host: host,
      probe: const SudoersFileExistsProbe(),
      facts: resolved,
    );
  } catch (_) {
    fileExists = false;
  }
  if (!context.mounted) {
    return false;
  }

  final initial = preselected ?? defaultKelolaSudoersGroups(resolved);
  final selection = await showModalBottomSheet<Set<KelolaSudoersGroup>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _EnableSudoPreviewSheet(
      user: host.username,
      facts: resolved!,
      initial: initial,
      fileExists: fileExists,
    ),
  );
  if (selection == null || selection.isEmpty || !context.mounted) {
    return false;
  }

  final spec = buildKelolaSudoersSpec(
    user: host.username,
    facts: resolved,
    groups: selection,
  );

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => KelolaSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
        child: RiskBand(
          risk: RiskLevel.mutate,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                fileExists ? 'Replace $kelolaSudoersPath?' : 'Write $kelolaSudoersPath?',
                style: KelolaType.display(color: ctx.kc.text, size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Mode $kelolaSudoersMode. Kelola will ask for your sudo password '
                'once, validate with visudo, then discard the password. '
                'Daily probes stay passwordless (sudo -n).',
                style: KelolaType.body(color: ctx.kc.muted, size: 13),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(fileExists ? 'Replace' : 'Continue'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) {
    return false;
  }

  final password = EphemeralPassword();
  final lifecycle = _SudoPasswordLifecycle(password);
  WidgetsBinding.instance.addObserver(lifecycle);
  try {
    final entered = await showPasswordEntrySheet(
      context,
      password: password,
    );
    if (!entered || !context.mounted) {
      return false;
    }
    final pass = password.read();
    if (pass == null || pass.isEmpty) {
      password.clear();
      return false;
    }

    final groupsLabel = selection.map(kelolaSudoersGroupLabel).join(', ');
    try {
      await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        facts: resolved,
        probe: SudoersInstallProbe(spec: spec, groupsLabel: groupsLabel),
        stdinBytes: utf8.encode('$pass\n'),
      );
      await ref.read(hostRepositoryProvider).setSudoNeedsPassword(host.id, false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('sudoers installed · verified')),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is KelolaException ? e.message : 'sudoers install failed',
            ),
          ),
        );
      }
      return false;
    } finally {
      password.clear();
    }
  } finally {
    WidgetsBinding.instance.removeObserver(lifecycle);
    password.clear();
  }
}

class _SudoPasswordLifecycle with WidgetsBindingObserver {
  _SudoPasswordLifecycle(this._password);

  final EphemeralPassword _password;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _password.clear();
    }
  }
}

class _EnableSudoPreviewSheet extends StatefulWidget {
  const _EnableSudoPreviewSheet({
    required this.user,
    required this.facts,
    required this.initial,
    required this.fileExists,
  });

  final String user;
  final HostFacts facts;
  final Set<KelolaSudoersGroup> initial;
  final bool fileExists;

  @override
  State<_EnableSudoPreviewSheet> createState() =>
      _EnableSudoPreviewSheetState();
}

class _EnableSudoPreviewSheetState extends State<_EnableSudoPreviewSheet> {
  late Set<KelolaSudoersGroup> _groups;

  @override
  void initState() {
    super.initState();
    _groups = {...widget.initial};
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final available = defaultKelolaSudoersGroups(widget.facts);
    final spec = buildKelolaSudoersSpec(
      user: widget.user,
      facts: widget.facts,
      groups: _groups,
    );
    return KelolaSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enable Kelola sudo',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Writes $kelolaSudoersPath (mode $kelolaSudoersMode). '
              '${widget.fileExists ? 'File already exists and will be replaced if you continue. ' : ''}'
              'Optional — Kelola stays useful with zero sudo.',
              style: KelolaType.body(color: c.muted, size: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final g in KelolaSudoersGroup.values)
                  FilterPill(
                    label: kelolaSudoersGroupLabel(g),
                    selected: _groups.contains(g),
                    enabled: available.contains(g) ||
                        g == KelolaSudoersGroup.hostPower,
                    onTap: () => setState(() {
                      if (_groups.contains(g)) {
                        _groups.remove(g);
                      } else {
                        _groups.add(g);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: c.surface2,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(KelolaRadii.sm),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  spec.content,
                  style: KelolaType.mono(color: c.text, size: 11),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _groups.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_groups),
              child: const Text('Review and apply'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens enable flow with feature group preselected when possible.
Future<void> openEnableKelolaSudoFromHint({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  HostFacts? facts,
  SudoHintKind? kind,
}) {
  Set<KelolaSudoersGroup>? pre;
  if (kind == SudoHintKind.packages) {
    pre = {KelolaSudoersGroup.packages};
  } else if (kind == SudoHintKind.firewall) {
    pre = {KelolaSudoersGroup.firewall};
  } else if (kind == SudoHintKind.hostReboot ||
      kind == SudoHintKind.hostPoweroff) {
    pre = {KelolaSudoersGroup.hostPower};
  }
  return runEnableKelolaSudoFlow(
    context: context,
    ref: ref,
    host: host,
    facts: facts,
    preselected: pre,
  ).then((_) {});
}
