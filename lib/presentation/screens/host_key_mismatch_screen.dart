import 'package:flutter/material.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/presentation/widgets/risk_band.dart';

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
    return KelolaPage(
      title: 'Host key changed',
      kicker: 'DO NOT CONTINUE BLINDLY',
      body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RiskBand(
                level: RiskLevel.destructive,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The key for $hostAlias has changed.',
                      style: KelolaFonts.title(size: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This can mean the server was rebuilt — or that something is intercepting.',
                      style: TextStyle(color: colors.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const KelolaSection('Pinned'),
              const SizedBox(height: 8),
              KelolaPanel(
                child: SelectableText(pinned, style: KelolaFonts.machine()),
              ),
              const SizedBox(height: 14),
              const KelolaSection('Seen'),
              const SizedBox(height: 8),
              KelolaPanel(
                accent: colors.red,
                child: SelectableText(seen, style: KelolaFonts.machine()),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
    );
  }
}
