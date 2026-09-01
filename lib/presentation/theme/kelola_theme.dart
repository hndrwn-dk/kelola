import 'package:flutter/material.dart';
import 'package:kelola/domain/risk/risk_level.dart';

@immutable
class KelolaColors extends ThemeExtension<KelolaColors> {
  const KelolaColors({
    required this.ink,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.muted,
    required this.dim,
    required this.amber,
    required this.red,
    required this.green,
    required this.blue,
  });

  final Color ink;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color text;
  final Color muted;
  final Color dim;
  final Color amber;
  final Color red;
  final Color green;
  final Color blue;

  static const dark = KelolaColors(
    ink: Color(0xFF0E1116),
    surface: Color(0xFF161A21),
    surface2: Color(0xFF1E242D),
    line: Color(0xFF2A323D),
    text: Color(0xFFE4E8EE),
    muted: Color(0xFF8A95A5),
    dim: Color(0xFF5C6675),
    amber: Color(0xFFF0A02C),
    red: Color(0xFFE5484D),
    green: Color(0xFF46A758),
    blue: Color(0xFF5B8DEF),
  );

  Color risk(RiskLevel level) {
    switch (level) {
      case RiskLevel.read:
        return dim;
      case RiskLevel.mutate:
        return amber;
      case RiskLevel.destructive:
        return red;
    }
  }

  @override
  KelolaColors copyWith({
    Color? ink,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? text,
    Color? muted,
    Color? dim,
    Color? amber,
    Color? red,
    Color? green,
    Color? blue,
  }) {
    return KelolaColors(
      ink: ink ?? this.ink,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      line: line ?? this.line,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      dim: dim ?? this.dim,
      amber: amber ?? this.amber,
      red: red ?? this.red,
      green: green ?? this.green,
      blue: blue ?? this.blue,
    );
  }

  @override
  ThemeExtension<KelolaColors> lerp(ThemeExtension<KelolaColors>? other, double t) {
    return this;
  }
}

ThemeData kelolaTheme() {
  const colors = KelolaColors.dark;
  final scheme = ColorScheme.dark(
    surface: colors.ink,
    primary: colors.amber,
    onPrimary: const Color(0xFF1A1206),
    secondary: colors.muted,
    error: colors.red,
    onSurface: colors.text,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.ink,
    extensions: const [colors],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.ink,
      foregroundColor: colors.text,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.amber),
      ),
    ),
  );
}
