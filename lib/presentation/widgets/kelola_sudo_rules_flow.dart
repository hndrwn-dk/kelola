import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/sudo/kelola_sudo_files.dart';
import 'package:kelola/presentation/destructive_auth.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/enable_kelola_sudo_flow.dart';
import 'package:kelola/providers.dart';

const _title = 'Sudo password';
const _body =
    'Enter your sudo password for this host. Kelola uses it once and does '
    'not store it.';

/// Asks for the sudo password once (cleared when the app leaves the
/// foreground), then runs [use] with it. Null when no password was given.
Future<T?> _withSudoPassword<T>(
  BuildContext context,
  Future<T> Function(String password) use,
) async {
  final password = EphemeralPassword();
  final lifecycle = SudoPasswordLifecycle(password);
  WidgetsBinding.instance.addObserver(lifecycle);
  try {
    final entered = await showPasswordEntrySheet(
      context,
      password: password,
      title: _title,
      body: _body,
    );
    final pass = password.read();
    if (!entered || pass == null || pass.isEmpty || !context.mounted) {
      return null;
    }
    return await use(pass);
  } finally {
    WidgetsBinding.instance.removeObserver(lifecycle);
    password.clear();
  }
}

/// Host details: reads the Kelola sudo files with the sudo password
/// (stdin). Cancelled, it reads them without one, as before.
Future<KelolaSudoFiles> readKelolaSudoFilesWithPassword({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  HostFacts? facts,
}) async {
  final read = await _withSudoPassword(
    context,
    (pass) => runHostProbe(
      ref: ref,
      context: context,
      host: host,
      facts: facts,
      probe: const KelolaSudoFilesProbe(withPassword: true),
      stdinBytes: utf8.encode('$pass\n'),
    ),
  );
  if (read != null) return read;
  if (!context.mounted) throw KelolaException('Nothing was read.');
  return runHostProbe(
    ref: ref,
    context: context,
    host: host,
    facts: facts,
    probe: const KelolaSudoFilesProbe(),
  );
}

/// Host details: removes one line or a whole Kelola sudo file, after the
/// screen's confirm sheet. A fresh presence prompt first (destructive), then
/// the sudo password over stdin, then [KelolaSudoRemoveProbe]. The probe
/// refuses any path outside [kelolaOwnedSudoersFiles] before anything runs.
/// Throws when nothing was changed.
Future<void> removeKelolaSudoRule({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  required KelolaSudoRemoval removal,
  HostFacts? facts,
}) async {
  final probe = KelolaSudoRemoveProbe(path: removal.path, line: removal.line);
  await requireDestructivePresence(
    ref.read(hardwareSignerProvider),
    risk: probe.risk,
    reason: probe.auditTitle,
  );
  if (!context.mounted) throw KelolaException('Nothing was changed.');
  final done = await _withSudoPassword(
    context,
    (pass) => runHostProbe(
      ref: ref,
      context: context,
      host: host,
      facts: facts,
      probe: probe,
      stdinBytes: utf8.encode('$pass\n'),
    ),
  );
  if (done == null) throw KelolaException('Nothing was changed.');
}
