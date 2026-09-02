import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

class TofuScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return KelolaPage(
      title: 'Unknown host key',
      kicker: 'TRUST ON FIRST USE',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This is the first time Kelola has seen this host. Accept the fingerprint to pin it.',
              style: TextStyle(color: colors.muted, height: 1.5),
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
                    style: KelolaFonts.machine(size: 13),
                  ),
                ],
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () async {
                await ref.read(hostRepositoryProvider).pinKey(
                      hostId: hostId,
                      algorithm: algorithm,
                      fingerprint: fingerprint,
                    );
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Pin and continue'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
