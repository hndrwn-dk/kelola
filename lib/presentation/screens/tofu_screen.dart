import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

/// First-seen host key. Pinning is a new trust decision, so it always asks
/// for a fresh biometric even while the signing key's 300s window is open
/// (otherwise a host added right after another one never prompts).
class TofuScreen extends ConsumerStatefulWidget {
  const TofuScreen({
    super.key,
    required this.hostId,
    required this.algorithm,
    required this.fingerprint,
  });

  final String hostId;
  final String algorithm;
  final String fingerprint;

  @override
  ConsumerState<TofuScreen> createState() => _TofuScreenState();
}

class _TofuScreenState extends ConsumerState<TofuScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _pin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(hardwareSignerProvider)
          .confirmPresence(reason: 'Pin host key');
    } catch (_) {
      _fail('Fingerprint not confirmed. The host key was not pinned.');
      return;
    }
    try {
      await ref.read(hostRepositoryProvider).pinKey(
            hostId: widget.hostId,
            algorithm: widget.algorithm,
            fingerprint: widget.fingerprint,
          );
    } catch (_) {
      _fail('Could not save the host key on this phone. It was not pinned.');
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _fail(String message) {
    if (mounted) {
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final hostId = widget.hostId;
    final algorithm = widget.algorithm;
    final fingerprint = widget.fingerprint;
    return KelolaPage(
      title: 'Unknown host key',
      bar: KelolaHostAppBar(
        hostAlias: watchedHostAlias(ref, hostId),
        title: 'Unknown host key',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This is the first time Kelola has seen this host. Accept the fingerprint to pin it.',
              style: KelolaType.body(color: c.muted, size: 15),
            ),
            const SizedBox(height: 18),
            KelolaPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KelolaSection(algorithm),
                  const SizedBox(height: 8),
                  SelectableText(
                    fingerprint,
                    style: KelolaType.mono(color: c.text, size: 13),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              KelolaError(message: _error!),
            ],
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _pin,
              child: const Text('Pin and continue'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
