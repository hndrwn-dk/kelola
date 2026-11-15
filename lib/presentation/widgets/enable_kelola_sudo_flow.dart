import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/sudo_flavor_probe.dart';
import 'package:kelola/domain/probes/sudoers_install_probe.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';
import 'package:kelola/domain/services/web_lens.dart';
import 'package:kelola/presentation/screens/web_lens_screen.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/unit_sudoers_grant.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/providers.dart';

const _sudoPasswordTitle = 'Sudo password';
const _sudoPasswordBody =
    'Enter your sudo password for this host. Kelola uses it once and does not store it.';

String kelolaSudoersGroupLabel(KelolaSudoersGroup g) {
  return switch (g) {
    KelolaSudoersGroup.packages => 'Packages',
    KelolaSudoersGroup.firewall => 'Firewall',
    KelolaSudoersGroup.hostPower => 'Host power',
    KelolaSudoersGroup.services => 'Services',
    KelolaSudoersGroup.processes => 'Processes',
    KelolaSudoersGroup.containers => 'Containers',
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
/// Host power, Services, Processes, Containers when present). No per-group
/// picker.
///
/// [hint] is the failure that led here. On a host without regex rules the full
/// set cannot cover a service action, so a service [hint] offers that one
/// action instead.
Future<bool> runEnableKelolaSudoFlow({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  HostFacts? facts,
  SudoHintContext? hint,
  DetectedService? webService,
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

  final grant = hint == null ||
          sudo.supportsArgRegex ||
          resolved.init != InitSystem.systemd
      ? null
      : UnitSudoersGrant.fromHint(hint, host.username);
  if (grant != null) {
    return _runUnitGrantFlow(
      context: context,
      ref: ref,
      host: host,
      facts: resolved,
      grant: grant,
    );
  }

  final groups = defaultKelolaSudoersGroups(resolved, sudo: sudo);
  if (groups.isEmpty) {
    return false;
  }
  // One tap covers the web lenses too (M52c): their exact read lines go to
  // kelola-web with the same password, through the same host-side checks.
  final webServices = await _hostWebLensServices(ref, host, webService);
  if (!context.mounted) {
    return false;
  }
  final webLabel = webServices.isEmpty
      ? ''
      : ' Also adds exact read-only lines for the '
            '${webServices.map((s) => descriptorFor(s.id).label).join(' and ')} '
            'lens to $kelolaWebSudoersPath.';

  // The exact lens lines the preview shows; anything else the host names
  // later is shown again before it is written.
  final previewed = <ServiceId, List<String>>{
    for (final s in webServices)
      s.id:
          webReadGrantFor(host: host, service: s, facts: resolved)?.lines ??
          const [],
  };

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
      webLines: [for (final s in webServices) ...?previewed[s.id]],
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
                '${kelolaSudoersGroupsLabel(groups)}.$webLabel '
                'Kelola will ask for your sudo password once, validate with '
                'visudo, then discard the password. Daily probes stay '
                'passwordless (sudo -n).',
                style: KelolaType.body(color: ctx.kc.muted, size: 13),
              ),
              if (webServices.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  webGrantSheetFooter,
                  style: KelolaType.body(color: ctx.kc.dim, size: 12),
                ),
              ],
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
      title: _sudoPasswordTitle,
      body: _sudoPasswordBody,
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
      final notes = <GrantNote>[];
      for (final service in webServices) {
        if (!context.mounted) break;
        notes.addAll(
          await _installWebLensRules(
            context: context,
            ref: ref,
            host: host,
            facts: resolved,
            service: service,
            previewed: previewed[service.id] ?? const [],
            password: password.read,
          ),
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('sudoers installed · verified')),
        );
      }
      if (notes.isNotEmpty && context.mounted) {
        // Not awaited: the caller reads again behind it.
        unawaited(showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (ctx) => KelolaSheet(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
              child: grantNotesText(
                ctx,
                notes: notes,
                style: KelolaType.body(color: ctx.kc.muted, size: 13),
              ),
            ),
          ),
        ));
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

/// M52c: the host's own nginx / Apache services (never a container) from the
/// STACK cache, plus [current] (the lens that asked), one per id.
Future<List<DetectedService>> _hostWebLensServices(
  WidgetRef ref,
  Host host,
  DetectedService? current,
) async {
  ServiceDetection? cached;
  try {
    final store = await ref.read(serviceLensStoreProvider.future);
    cached = await store.read(host.id);
  } catch (_) {
    cached = null;
  }
  final byId = <ServiceId, DetectedService>{};
  for (final s in [?current, ...?cached?.services]) {
    if (hasLens(s.id) && !s.inContainer) {
      byId.putIfAbsent(s.id, () => s);
    }
  }
  return byId.values.toList();
}

/// M52c: installs [service]'s lens read lines in [kelolaWebSudoersPath] with
/// the password the user already gave, through the same `WebSudoersGrant`
/// and host-side checks as the old per-lens grant. Certificate and log
/// paths come from the config dump, which may need the first lines, so the
/// lens is read again once and a second round adds what it found. Only
/// [previewed] lines and lines the user adds in [confirmExtraWebLensLines]
/// are written. [password] is read before each write; null (cleared) stops.
/// Returns what the host left out; a failure here never undoes the main
/// file.
Future<List<GrantNote>> _installWebLensRules({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  required HostFacts facts,
  required DetectedService service,
  required List<String> previewed,
  required String? Function() password,
}) async {
  final notes = <GrantNote>[];
  Future<WebLens?> read() async {
    try {
      return await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        facts: facts,
        probe: WebLensProbe(
          id: service.id,
          binaries: service.binaries,
          unit: service.unit,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  final approved = <String>{...previewed};
  final declined = <String>{};
  final installed = <String>{};
  for (var round = 0; round < 2 && context.mounted; round++) {
    final lens = await read();
    if (!context.mounted) break;
    final full = webReadGrantFor(
      host: host,
      service: service,
      facts: facts,
      lens: lens,
    );
    if (full == null) break;
    final extra = [
      for (final l in full.lines)
        if (!approved.contains(l) && !declined.contains(l)) l,
    ];
    if (extra.isNotEmpty) {
      final ok = await confirmExtraWebLensLines(
        context: context,
        service: service,
        lines: extra,
      );
      if (!context.mounted) break;
      (ok ? approved : declined).addAll(extra);
    }
    final grant = full.onlyLines(approved);
    if (grant == null || grant.lines.every(installed.contains)) break;
    final pass = password();
    if (pass == null || pass.isEmpty) break;
    try {
      final r = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        facts: facts,
        probe: WebSudoersGrantProbe(grant),
        stdinBytes: utf8.encode('$pass\n'),
      );
      notes
        ..clear()
        ..addAll(webGrantNotes(config: r.config, skipped: r.skipped));
    } on WebGrantRefusedException catch (e) {
      notes
        ..clear()
        ..addAll(webGrantNotes(config: e.config, skipped: e.skipped));
    } on KelolaException catch (e) {
      // e.g. an untrusted binary: nothing installed for this lens.
      notes
        ..clear()
        ..add((lead: e.message, path: '', tail: ''));
      break;
    } catch (_) {
      break;
    }
    installed.addAll(grant.lines);
    // A full lens read already named the certificates and logs.
    if (lens != null) break;
  }
  return notes;
}

/// Title of the sheet that shows lens lines found after the preview.
String webExtraLinesTitle(DetectedService service) =>
    'Add ${descriptorFor(service.id).label} certificate and log lines?';

/// Body of that sheet.
const webExtraLinesBody =
    'The server config names these files. Each line lets this login read '
    'that file as root without a password. Kelola writes them only if you '
    'add them here; skipped lines are not written.';

/// Shows [lines] (exact, mono) for [kelolaWebSudoersPath], found after the
/// preview, and returns true only when the user taps Add lines. Uses the
/// password already given; never asks again.
Future<bool> confirmExtraWebLensLines({
  required BuildContext context,
  required DetectedService service,
  required List<String> lines,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.kc;
      return KelolaSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
          child: RiskBand(
            risk: RiskLevel.mutate,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  webExtraLinesTitle(service),
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  webExtraLinesBody,
                  style: KelolaType.body(color: c.muted, size: 13),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      '$kelolaWebSudoersPath\n${lines.join('\n')}',
                      style: KelolaType.mono(color: c.text, size: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Skip'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Add lines'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok == true;
}

/// Confirms and installs one service action. See [UnitSudoersGrant].
Future<bool> _runUnitGrantFlow({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  required HostFacts facts,
  required UnitSudoersGrant grant,
}) {
  return _runExactGrantFlow(
    context: context,
    ref: ref,
    host: host,
    facts: facts,
    title: 'Allow ${grant.action}?',
    body: "This host's sudo cannot match a service by pattern, so "
        'Kelola adds one rule for this action on this service. '
        'Other services and actions are unchanged. Remove the line '
        'on the host to undo it.',
    path: kelolaUnitSudoersPath,
    lines: [grant.line],
    confirmLabel: 'Add rule',
    probe: UnitSudoersGrantProbe(grant),
    done: '${grant.action} allowed · try it again',
    failed: 'Could not add the sudo rule',
  );
}

/// M52c: the one-tap preview cannot list certificate and log lines yet.
const webOneTapCertsLaterNote =
    'Certificate and log lines for each lens are shown for one more tap once '
    'the config can be read, and pass the same checks. Lines already in '
    '$kelolaWebSudoersPath are kept; remove stale ones on the host by hand.';

/// The web grant sheet's trade-off line (fix 1: enforced on the host).
const webGrantSheetFooter =
    'These rules let this login run the listed commands as root. The config '
    'test loads modules named in the server config, so Kelola adds it only '
    'when that config and its module directories are root-owned and not '
    'writable by others.';

/// One line of grant result copy: [lead], a host path, [tail].
typedef GrantNote = ({String lead, String path, String tail});

/// The "not granted" lines for a web grant result, config test first.
List<GrantNote> webGrantNotes({
  WebGrantConfigRefusal? config,
  List<String> skipped = const [],
}) => [
  if (config != null) webGrantConfigCopyParts(config),
  ...skipped.map(webGrantSkippedCopyParts),
];

/// [notes] as one text, each on its own line after [head] (if any), with
/// every host path in mono. [style] is the human copy's style.
Text grantNotesText(
  BuildContext context, {
  String? head,
  required List<GrantNote> notes,
  required TextStyle style,
}) {
  final mono = KelolaType.mono(
    color: style.color ?? context.kc.text,
    size: style.fontSize ?? 13,
  );
  final spans = <InlineSpan>[];
  for (final n in notes) {
    if (spans.isNotEmpty || head != null) spans.add(const TextSpan(text: '\n'));
    spans
      ..add(TextSpan(text: n.lead))
      ..add(TextSpan(text: n.path, style: mono))
      ..add(TextSpan(text: n.tail));
  }
  return Text.rich(
    TextSpan(text: head, style: style, children: spans),
  );
}

/// Shows [lines] (exact, mono) for [path], asks for the sudo password once,
/// passes it on stdin to [probe], then discards it.
Future<bool> _runExactGrantFlow({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  required HostFacts facts,
  required String title,
  required String body,
  String? note,
  String? footer,
  required String path,
  required List<String> lines,
  required String confirmLabel,
  required Probe<Object?> probe,
  required String done,
  List<GrantNote> Function(Object? result)? doneNotes,
  List<GrantNote>? Function(Object error)? errorNotes,
  required String failed,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.kc;
      return KelolaSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
          child: RiskBand(
            risk: RiskLevel.mutate,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: KelolaType.body(color: c.muted, size: 13),
                ),
                if (note != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    note,
                    style: KelolaType.body(color: c.muted, size: 13),
                  ),
                ],
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      '$path\n${lines.join('\n')}',
                      style: KelolaType.mono(color: c.text, size: 11),
                    ),
                  ),
                ),
                if (footer != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    footer,
                    style: KelolaType.body(color: c.muted, size: 13),
                  ),
                ],
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
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
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
      title: _sudoPasswordTitle,
      body: _sudoPasswordBody,
    );
    if (!entered || !context.mounted) {
      return false;
    }
    final pass = password.read();
    if (pass == null || pass.isEmpty) {
      return false;
    }
    try {
      final result = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        facts: facts,
        probe: probe,
        stdinBytes: utf8.encode('$pass\n'),
      );
      final notes = doneNotes?.call(result) ?? const <GrantNote>[];
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: notes.isEmpty
                ? Text(done)
                : Builder(
                    builder: (ctx) => grantNotesText(
                      ctx,
                      head: done,
                      notes: notes,
                      style: DefaultTextStyle.of(ctx).style,
                    ),
                  ),
          ),
        );
      }
      return true;
    } catch (e) {
      final notes = errorNotes?.call(e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: notes != null && notes.isNotEmpty
                ? Builder(
                    builder: (ctx) => grantNotesText(
                      ctx,
                      notes: notes,
                      style: DefaultTextStyle.of(ctx).style,
                    ),
                  )
                : Text(e is KelolaException ? e.message : failed),
          ),
        );
      }
      return false;
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
    this.webLines = const [],
  });

  /// M52c: the first exact lens lines for [kelolaWebSudoersPath]; certificate
  /// and log lines follow once the config can be read.
  final List<String> webLines;

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
                  [
                    spec.content.trimRight(),
                    if (webLines.isNotEmpty) ...[
                      '',
                      '# path: $kelolaWebSudoersPath  mode: 0440',
                      ...webLines,
                    ],
                  ].join('\n'),
                  style: KelolaType.mono(color: c.text, size: 11),
                ),
              ),
            ),
            if (webLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                webOneTapCertsLaterNote,
                style: KelolaType.body(color: c.muted, size: 12),
              ),
            ],
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
