import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/host_key_mismatch_screen.dart';
import 'package:kelola/presentation/ssh_host_key_flow.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart' show keyBackendLabel;
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

class EnrollmentScreen extends ConsumerStatefulWidget {
  const EnrollmentScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen> {
  String? _error;
  bool _busy = false;

  Future<void> _installWithPassword() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final verified = await runPasswordKeyInstallFlow(
        context: context,
        ref: ref,
        hostId: widget.hostId,
      );
      if (!mounted) {
        return;
      }
      if (verified) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => HostDashboardScreen(hostId: widget.hostId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(enrollmentProvider.notifier).ensureKey();
      final host = await ref.read(hostRepositoryProvider).get(widget.hostId);
      if (host == null) {
        return;
      }
      await ref.read(sessionPoolProvider).execute(
            host,
            const HostFactsProbe(),
            onUnknownHostKey: (hostId, algorithm, fingerprint) {
              return promptUnknownHostKey(
                context,
                hostId: hostId,
                algorithm: algorithm,
                fingerprint: fingerprint,
              );
            },
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HostDashboardScreen(hostId: widget.hostId),
        ),
      );
    } on HostKeyMismatchException catch (e) {
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HostKeyMismatchScreen(
            hostAlias: widget.hostId,
            pinned: e.pinnedFingerprint,
            seen: e.seenFingerprint,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _regenerate() async {
    final confirmed = await showMutateConfirm(
      context,
      title: 'Replace this phone\'s key?',
      body:
          'Kelola keeps one hardware key per phone and reuses it for every host. Regenerating makes the current line invalid; you must update authorized_keys on every server.',
      confirmLabel: 'Replace key',
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(enrollmentProvider.notifier).regenerateKey();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  static String _manualInstallCommands(String authorizedKeysLine) {
    return "mkdir -p ~/.ssh && chmod 700 ~/.ssh\n"
        "echo '$authorizedKeysLine' >> ~/.ssh/authorized_keys\n"
        'chmod 600 ~/.ssh/authorized_keys';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final enrollment = ref.watch(enrollmentProvider);
    final line = enrollment.authorizedKeysLine ?? 'generating…';
    final blob = enrollment.publicBlob;
    final fingerprint = blob == null
        ? null
        : OpensshEcdsaP256.fingerprintSha256(blob);
    final installBlock =
        blob == null ? null : _manualInstallCommands(line);

    return KelolaPage(
      title: 'Add the key',
      kicker: 'ONE KEY PER PHONE',
      busy: _busy,
      body: ListView(
        padding: kelolaScrollPadding(
          context,
          left: 16,
          top: 16,
          right: 16,
          extraBottom: 16,
        ),
        children: [
          Text(
            'Installing this key needs existing access to the host — '
            'another SSH session, a web console, or physical access.',
            style: KelolaType.body(color: c.muted, size: 13),
          ),
          const SizedBox(height: 18),
          Text(
            'PUBLIC KEY',
            style: KelolaType.mono(
              color: c.dim,
              size: 8.5,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 8),
          KelolaCommand(command: line),
          if (installBlock != null) ...[
            const SizedBox(height: 18),
            Text(
              'MANUAL INSTALL',
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
            const SizedBox(height: 8),
            KelolaCommand(command: installBlock),
          ],
          if (fingerprint != null) ...[
            const SizedBox(height: 18),
            Text(
              'FINGERPRINT',
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fingerprint,
              style: KelolaType.mono(color: c.text, size: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'RHEL-family hosts may need restorecon -R ~/.ssh if '
              '~/.ssh was created outside Kelola\'s bootstrap.',
              style: KelolaType.body(color: c.dim, size: 12),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _installWithPassword,
            child: Text(
              _busy ? 'Working…' : 'Install with password',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _test,
            child: Text(_busy ? 'Testing…' : 'Test connection'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _regenerate,
              child: const Text('Replace this phone\'s key'),
            ),
          ),
          if (enrollment.backendLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              'Backend: ${keyBackendLabel(enrollment.backendLabel)}',
              style: KelolaType.mono(color: c.dim, size: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'This phone has one hardware key, reused for every host. '
            'A new VM does not create a new key.',
            style: KelolaType.body(color: c.dim, size: 12),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            KelolaError(message: _error!),
          ],
        ],
      ),
    );
  }
}
