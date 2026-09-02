import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/host_key_mismatch_screen.dart';
import 'package:kelola/presentation/ssh_host_key_flow.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';
import 'package:qr_flutter/qr_flutter.dart';

class EnrollmentScreen extends ConsumerStatefulWidget {
  const EnrollmentScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen> {
  String? _error;
  bool _busy = false;

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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final enrollment = ref.watch(enrollmentProvider);
    final line = enrollment.authorizedKeysLine ?? 'generating…';

    return KelolaPage(
      title: 'Add the key',
      kicker: 'ONE KEY PER PHONE',
      busy: _busy,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Scan this on the server, or copy the line into ~/.ssh/authorized_keys. No network needed.',
            style: TextStyle(color: colors.muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          if (enrollment.publicBlob != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.text,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: line,
                  size: 180,
                  backgroundColor: colors.text,
                ),
              ),
            ),
          const SizedBox(height: 16),
          KelolaCommand(command: line),
          const SizedBox(height: 14),
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
              style: KelolaFonts.machine(color: colors.dim, size: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'This phone has one hardware key, reused for every host. A new VM does not create a new key.',
            style: TextStyle(color: colors.dim, fontSize: 12, height: 1.45),
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
