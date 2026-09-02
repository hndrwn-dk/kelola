import 'package:flutter/material.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';

class SessionChrome extends StatelessWidget {
  const SessionChrome({
    super.key,
    required this.live,
    this.rttMs,
    this.backendLabel,
  });

  final bool live;
  final int? rttMs;
  final String? backendLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final bits = <String>[
      if (live) 'session up' else 'signed by this phone',
      if (live && rttMs != null) '${rttMs}ms',
      if (backendLabel != null) keyBackendLabel(backendLabel),
    ];
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: live ? colors.green : colors.dim,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            bits.join(' · ').toUpperCase(),
            style: KelolaFonts.machine(color: colors.dim, size: 10).copyWith(
              letterSpacing: 0.08,
            ),
          ),
        ),
      ],
    );
  }
}
