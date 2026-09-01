import 'package:flutter/material.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';

class HostKeyMismatchScreen extends StatelessWidget {
  const HostKeyMismatchScreen({
    super.key,
    required this.hostAlias,
    required this.pinned,
    required this.seen,
  });

  final String hostAlias;
  final String pinned;
  final String seen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Scaffold(
      backgroundColor: colors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The key for $hostAlias has changed.',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This can mean the server was rebuilt — or that something is intercepting.',
                style: TextStyle(color: colors.muted),
              ),
              const SizedBox(height: 20),
              Text('Pinned', style: TextStyle(color: colors.dim)),
              SelectableText(pinned, style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 12),
              Text('Seen', style: TextStyle(color: colors.dim)),
              SelectableText(seen, style: const TextStyle(fontFamily: 'monospace')),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
