import 'package:flutter/material.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';

/// Inter: labels and titles. JetBrains Mono: metrics, IPs, PIDs, paths.
abstract final class KelolaFonts {
  static const display = 'Inter';
  static const body = 'Inter';
  static const mono = 'JetBrainsMono';

  static const tabular = [FontFeature.tabularFigures()];

  static TextStyle title({Color? color, double size = 16}) {
    return TextStyle(
      fontFamily: display,
      fontWeight: FontWeight.w600,
      fontSize: size,
      letterSpacing: -0.2,
      color: color,
    );
  }

  static TextStyle machine({
    Color? color,
    double size = 11,
    FontWeight weight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: mono,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: 0.02,
      height: 1.45,
      color: color,
      fontFeatures: tabular,
    );
  }

  static TextStyle eyebrow(KelolaColors colors) {
    return TextStyle(
      fontFamily: mono,
      fontSize: 10,
      letterSpacing: 0.14,
      color: colors.dim,
      height: 1.2,
      fontFeatures: tabular,
    );
  }
}
