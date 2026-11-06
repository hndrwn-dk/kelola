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
import 'package:kelola/domain/probes/sudo_flavor_probe.dart';
import 'package:kelola/domain/probes/sudoers_install_probe.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/providers.dart';

String kelolaSudoersGroupLabel(KelolaSudoersGroup g) {
  return switch (g) {
    KelolaSudoersGroup.packages => 'Packages',
    KelolaSudoersGroup.firewall => 'Firewall',
    KelolaSudoersGroup.hostPower => 'Host power',
    KelolaSudoersGroup.services => 'Services',
    KelolaSudoersGroup.processes => 'Processes',
  };
}

String kelolaSudoersGroupsLabel(Set<KelolaSudoersGroup> groups) {
  return KelolaSudoersGroup.values
      .where(groups.contains)
      .map(kelolaSudoersGroupLabel)
      .join(', ');
}

/// Guided install of [kelolaSudoersPath]. Returns true on verified install.
///
/// Always installs the full set available for [facts] (Packages, Firewall,
/// Host power, Services, Processes when present). No per-group picker.
Future<bool> runEnableKelolaSudoFlow({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  HostFacts? facts,
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

  SudoFlavor sudo = const UnknownSudo();
  try {
    sudo = await runHostProbe(
      ref: ref,
      context: context,
      host: host,
      probe: const SudoFlavorProbe(),
      facts: resolved,
    );
  } catch (_) {
    sudo = const UnknownSudo();
  }
  if (!context.mounted) {
    return false;
  }

  final groups = defaultKelolaSudoersGroups(resolved, sudo: sudo);
  if (groups.isEmpty) {
    return false;
  }

  final reviewed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _EnableSudoPreviewSheet(
      user: host.username,
      facts: resolved!,
      groups: groups,
      sudo: sudo,
      fileExists: fileExists,
    ),
  );
  if (reviewed != true || !context.mounted) {
    return false;
  }

  final spec = buildKelolaSudoersSpec(
    user: host.username,
    facts: resolved,
    groups: groups,
    sudo: sudo,
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
                fileExists
                    ? 'Replace $kelolaSudoersPath?'
                    : 'Write $kelolaSudoersPath?',
                style: KelolaType.display(color: ctx.kc.text, size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Mode $kelolaSudoersMode. Includes '
                '${kelolaSudoersGroupsLabel(groups)}. '
                'Kelola will ask for your sudo password once, validate with '
                'visudo, then discard the password. Daily probes stay '
                'passwordless (sudo -n).',
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

    final groupsLabel = kelolaSudoersGroupsLabel(groups);
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

class _EnableSudoPreviewSheet extends StatelessWidget {
  const _EnableSudoPreviewSheet({
    required this.user,
    required this.facts,
    required this.groups,
    required this.sudo,
    required this.fileExists,
  });

  final String user;
  final HostFacts facts;
  final Set<KelolaSudoersGroup> groups;
  final SudoFlavor sudo;
  final bool fileExists;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final spec = buildKelolaSudoersSpec(
      user: user,
      facts: facts,
      groups: groups,
      sudo: sudo,
    );
    final tierNote = kelolaSudoersTierNote(sudo);
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
              'Writes $kelolaSudoersPath (mode $kelolaSudoersMode) for '
              '${kelolaSudoersGroupsLabel(groups)}. '
              '${fileExists ? 'File already exists and will be replaced if you continue. ' : ''}'
              'Optional — Kelola stays useful with zero sudo.',
              style: KelolaType.body(color: c.muted, size: 13),
            ),
            if (tierNote != null) ...[
              const SizedBox(height: 8),
              Text(
                tierNote,
                style: KelolaType.body(color: c.muted, size: 13),
              ),
            ],
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
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Review and apply'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the same full-set enable flow from a sudo hint (Packages / Firewall / host).
Future<void> openEnableKelolaSudoFromHint({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  HostFacts? facts,
  SudoHintKind? kind,
}) {
  // [kind] is kept for call-site compatibility; apply is always the full set.
  return runEnableKelolaSudoFlow(
    context: context,
    ref: ref,
    host: host,
    facts: facts,
  ).then((_) {});
}
