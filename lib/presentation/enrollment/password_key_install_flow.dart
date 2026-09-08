import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/enrollment/key_install_outcome.dart';
import 'package:kelola/domain/enrollment/key_install_script.dart';
import 'package:kelola/domain/enrollment/password_auth_failure.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/screens/host_key_mismatch_screen.dart';
import 'package:kelola/presentation/ssh_host_key_flow.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

const _passwordDiscardedMessage = 'password discarded';

void showPasswordDiscardedMessage(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text(_passwordDiscardedMessage)),
  );
}

/// STEP 2 — obscured password entry. Cancel clears [password] then shows
/// [password discarded] only after clear.
Future<bool> showPasswordEntrySheet(
  BuildContext context, {
  required EphemeralPassword password,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => KelolaSheet(
      child: _PasswordEntryBody(
        onCancel: () => Navigator.of(ctx).pop(false),
        onSubmit: (value) {
          password.set(value);
          Navigator.of(ctx).pop(true);
        },
      ),
    ),
  );

  if (submitted == true) {
    return true;
  }

  password.clear();
  if (context.mounted) {
    showPasswordDiscardedMessage(context);
  }
  return false;
}

/// STEP 3 — confirm what will be written before append.
Future<bool> showInstallKeyConfirmSheet(
  BuildContext context, {
  required String fullLine,
  required String fingerprint,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.kc;
      return KelolaSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 0),
          child: RiskBand(
            risk: RiskLevel.mutate,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Install this key?',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kelola will append this line to ~/.ssh/authorized_keys.',
                  style: KelolaType.body(color: c.muted, size: 13),
                ),
                const SizedBox(height: 12),
                KelolaCommand(command: fullLine),
                const SizedBox(height: 12),
                Text(
                  'FINGERPRINT',
                  style: KelolaType.mono(
                    color: c.dim,
                    size: 8.5,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fingerprint,
                  style: KelolaType.mono(color: c.text, size: 12),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Install this key'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return confirmed == true;
}

/// Pre-append auth failure UI. Retry only when [failure.offerRetry].
///
/// Returns `true` when the user chooses retry.
Future<bool> showPasswordAuthFailureSheet(
  BuildContext context, {
  required PasswordAuthFailure failure,
  required bool passwordDiscarded,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.kc;
      return KelolaSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 0),
          child: RiskBand(
            risk: RiskLevel.read,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Password install failed',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  failure.message,
                  style: KelolaType.body(color: c.muted, size: 13),
                ),
                if (passwordDiscarded) ...[
                  const SizedBox(height: 10),
                  Text(
                    _passwordDiscardedMessage,
                    style: KelolaType.body(color: c.dim, size: 12),
                  ),
                ],
                const SizedBox(height: 14),
                if (failure.offerRetry)
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Try again'),
                  ),
                if (failure.offerRetry) const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Use manual path'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result == true;
}

Future<void> showKeyInstallReportSheet(
  BuildContext context, {
  required KeyInstallReport report,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.kc;
      return KelolaSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 0),
          child: RiskBand(
            risk: report.success ? RiskLevel.read : RiskLevel.mutate,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    report.title,
                    style: KelolaType.display(color: c.text, size: 16),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        report.body,
                        style: KelolaType.mono(color: c.text, size: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Full password-bootstrap install: host key → password → confirm → append →
/// fresh key verify → report. Clears [EphemeralPassword] on every exit.
Future<void> runPasswordKeyInstallFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String hostId,
  VoidCallback? onPasswordDiscarded,
}) async {
  final password = EphemeralPassword();
  final lifecycle = _PasswordLifecycleObserver(password);
  WidgetsBinding.instance.addObserver(lifecycle);

  void discardPassword({bool snackbar = false}) {
    password.clear();
    onPasswordDiscarded?.call();
    if (snackbar && context.mounted) {
      showPasswordDiscardedMessage(context);
    }
  }

  try {
    await ref.read(enrollmentProvider.notifier).ensureKey();
    final enrollment = ref.read(enrollmentProvider);
    final fullLine = enrollment.authorizedKeysLine;
    final blob = enrollment.publicBlob;
    if (fullLine == null || blob == null) {
      return;
    }
    final keyBody = fullLine.split(RegExp(r'\s+'))[1];
    final fingerprint = OpensshEcdsaP256.fingerprintSha256(blob);

    final host = await ref.read(hostRepositoryProvider).get(hostId);
    if (host == null) {
      return;
    }

    final pool = ref.read(sessionPoolProvider);
    final repo = ref.read(hostRepositoryProvider);

    while (context.mounted) {
      final entered = await showPasswordEntrySheet(
        context,
        password: password,
      );
      if (!entered) {
        // Sheet already cleared and showed discarded snackbar.
        onPasswordDiscarded?.call();
        return;
      }

      KeyInstallAppendResult? append;
      try {
        append = await pool.runPasswordBootstrap(
          host: host,
          password: password,
          onUnknownHostKey: (id, algorithm, fp) {
            return promptUnknownHostKey(
              context,
              hostId: id,
              algorithm: algorithm,
              fingerprint: fp,
            );
          },
          body: (client) async {
            if (!context.mounted) {
              return null;
            }
            final confirmed = await showInstallKeyConfirmSheet(
              context,
              fullLine: fullLine,
              fingerprint: fingerprint,
            );
            if (!confirmed) {
              return null;
            }
            // Append/exec errors are not credential failures — report unknown
            // file state via KeyInstallAppendKind.failed, not auth-mode UI.
            try {
              return await pool.appendAuthorizedKeysLine(
                client: client,
                keyBody: keyBody,
                fullLine: fullLine,
              );
            } catch (_) {
              return const KeyInstallAppendResult(
                kind: KeyInstallAppendKind.failed,
                homeMode: 'unknown',
                createdSsh: false,
              );
            }
          },
        );
      } on HostKeyMismatchException catch (e) {
        discardPassword(snackbar: true);
        if (!context.mounted) {
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HostKeyMismatchScreen(
              hostAlias: host.alias,
              pinned: e.pinnedFingerprint,
              seen: e.seenFingerprint,
            ),
          ),
        );
        return;
      } catch (e) {
        discardPassword();
        if (!context.mounted) {
          return;
        }
        final failure = classifySshBootstrapError(
          e,
          hostKeyAccepted: pool.lastHostKeyAccepted,
          hostKeyDeclined: pool.lastHostKeyDeclined,
          serverAuthMethods: pool.lastServerAuthMethods,
        );
        await repo.recordAudit(
          hostId: host.id,
          hostAlias: host.alias,
          remoteUser: host.username,
          title:
              'Password key install ${failure.mode.name} on ${host.alias}',
          command: 'kelola-key-install',
          risk: RiskLevel.mutate.name,
          usedSudo: false,
          errorSummary: failure.mode.name,
        );
        final retry = await showPasswordAuthFailureSheet(
          context,
          failure: failure,
          passwordDiscarded: true,
        );
        if (failure.offerRetry && retry) {
          continue;
        }
        return;
      }

      discardPassword(snackbar: true);

      if (append == null) {
        return;
      }

      var verifyOk = false;
      if (append.kind != KeyInstallAppendKind.failed) {
        final verified = await verifyAfterPasswordKeyInstall(
          context: context,
          pool: pool,
          host: host,
        );
        if (verified == null) {
          // Host-key mismatch UI already shown; do not present stray-key copy.
          return;
        }
        verifyOk = verified;
      }

      final report = buildKeyInstallReport(
        append: append,
        verifyOk: verifyOk,
        fullLine: fullLine,
      );

      await recordKeyInstallAudit(
        repo: repo,
        host: host,
        append: append,
        verifyOk: verifyOk,
        report: report,
      );

      if (!context.mounted) {
        return;
      }
      await showKeyInstallReportSheet(context, report: report);
      return;
    }
  } finally {
    password.clear();
    WidgetsBinding.instance.removeObserver(lifecycle);
  }
}

/// Fresh key-only verify after append. Returns `true`/`false` for verify
/// outcome, or `null` when [HostKeyMismatchException] was surfaced to the user.
Future<bool?> verifyAfterPasswordKeyInstall({
  required BuildContext context,
  required SshSessionPool pool,
  required Host host,
}) async {
  try {
    await pool.verifyFreshKeyAuth(
      host,
      const HostFactsProbe(),
      onUnknownHostKey: (id, algorithm, fp) {
        return promptUnknownHostKey(
          context,
          hostId: id,
          algorithm: algorithm,
          fingerprint: fp,
        );
      },
    );
    return true;
  } on HostKeyMismatchException catch (e) {
    // Do not fold mismatch into append-ok / verify-fail stray-key UI.
    if (!context.mounted) {
      return null;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostKeyMismatchScreen(
          hostAlias: host.alias,
          pinned: e.pinnedFingerprint,
          seen: e.seenFingerprint,
        ),
      ),
    );
    return null;
  } catch (_) {
    return false;
  }
}

@visibleForTesting
Future<void> recordKeyInstallAudit({
  required HostRepository repo,
  required Host host,
  required KeyInstallAppendResult append,
  required bool verifyOk,
  required KeyInstallReport report,
}) {
  final String title;
  final String note;
  if (append.kind == KeyInstallAppendKind.appended && verifyOk) {
    title = 'Added Kelola public key to ${host.alias}';
    note = 'append';
  } else if (append.kind == KeyInstallAppendKind.alreadyPresent && verifyOk) {
    title = 'Kelola public key already on ${host.alias}';
    note = 'already_present';
  } else if (append.kind == KeyInstallAppendKind.failed) {
    title = 'Password key install append failed on ${host.alias}';
    note = 'append_failed';
  } else {
    title = 'Password key install verify failed on ${host.alias}';
    note = append.kind == KeyInstallAppendKind.appended
        ? 'append_verify_failed'
        : 'already_present_verify_failed';
  }

  return repo.recordAudit(
    hostId: host.id,
    hostAlias: host.alias,
    remoteUser: host.username,
    title: title,
    command: 'kelola-key-install:$note',
    risk: RiskLevel.mutate.name,
    usedSudo: false,
    errorSummary: report.success ? null : report.title,
  );
}

class _PasswordLifecycleObserver with WidgetsBindingObserver {
  _PasswordLifecycleObserver(this._password);

  final EphemeralPassword _password;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _password.clear();
    }
  }
}

class _PasswordEntryBody extends StatefulWidget {
  const _PasswordEntryBody({
    required this.onCancel,
    required this.onSubmit,
  });

  final VoidCallback onCancel;
  final void Function(String value) onSubmit;

  @override
  State<_PasswordEntryBody> createState() => _PasswordEntryBodyState();
}

class _PasswordEntryBodyState extends State<_PasswordEntryBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 0),
      child: RiskBand(
        risk: RiskLevel.mutate,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Install with password',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the SSH password for this host. Kelola keeps it only '
              'in memory for this session.',
              style: KelolaType.body(color: c.muted, size: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              style: KelolaType.mono(color: c.text, size: 12),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: KelolaType.body(color: c.dim, size: 13),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KelolaRadii.sm),
                  borderSide: BorderSide(color: c.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KelolaRadii.sm),
                  borderSide: BorderSide(color: c.amber),
                ),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  widget.onSubmit(value);
                }
              },
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                final value = _controller.text;
                if (value.isEmpty) {
                  return;
                }
                widget.onSubmit(value);
              },
              child: const Text('Continue'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
