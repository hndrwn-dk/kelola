import 'package:flutter/material.dart';
import 'package:kelola/domain/risk/risk_level.dart';

export 'package:kelola/domain/risk/risk_level.dart';

/// Kelola design tokens — the single source of truth.
/// Mirrors DESIGN.html exactly. Never hardcode a color or radius
/// outside this file; import KelolaColors / KelolaRadii instead.
///
/// RiskLevel lives in domain/risk — the same enum on Probe.risk,
/// the dispatcher, and audit records. This file only maps it to color.
///
/// HealthStatus is presentation-only: how a host/unit/disk looks right
/// now. It is not an action gate and must never be stored on a Probe.

enum HealthStatus { healthy, warning, failed, unknown }

@immutable
class KelolaColors extends ThemeExtension<KelolaColors> {
  final Color ink;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color text;
  final Color muted;
  final Color dim;
  final Color amber;
  final Color amberDim;
  final Color red;
  final Color redDim;
  final Color green;
  final Color blue;

  const KelolaColors({
    required this.ink,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.text,
    required this.muted,
    required this.dim,
    required this.amber,
    required this.amberDim,
    required this.red,
    required this.redDim,
    required this.green,
    required this.blue,
  });

  /// Radial amber wash at the top of Hosts chrome (canvas: 18%).
  static const chromeWashOpacity = 0.18;

  /// 1px concentric arcs over the wash (canvas: 24–28%).
  static const chromeArcOpacity = 0.28;

  /// Group tray fill over chrome so ink + arcs read in padding and gutters.
  static const chromeTrayOpacity = 0.52;

  /// Footer hairline vs ink. `line` on `ink` vanishes on OLED.
  static const colophonHairlineOpacity = 0.28;

  /// Coolors-inspired Soft Navy + Warm Amber (C1), 60-30-10:
  /// - 60% neutralDeep `#0B1220`, neutralSoft `#152238`
  /// - 30% primary `#1E3A5F`, primaryBright `#2A4A6E`
  /// - 10% accent `#E8A03A`
  /// Sources: coolors.co/000814-001d3d-003566-ffc300-ffd60a (navy family),
  /// coolors.co/000000-14213d-fca311-e5e5e5-ffffff (gold accent, softened).
  /// Red/green remain semantic outliers (destructive / healthy), not brand.
  static const dark = KelolaColors(
    ink: Color(0xFF0B1220),
    surface: Color(0xFF152238),
    surface2: Color(0xFF1A2C44),
    surface3: Color(0xFF243A56),
    line: Color(0xFF2E4560),
    text: Color(0xFFD7DEE8),
    muted: Color(0xFF8B9BB0),
    dim: Color(0xFF5C6B7E),
    amber: Color(0xFFE8A03A),
    amberDim: Color(0xFF8A5F1E),
    red: Color(0xFFE5484D),
    redDim: Color(0xFF7A2528),
    green: Color(0xFF46A758),
    blue: Color(0xFF6B9BE8),
  );

  /// The one place RiskLevel becomes a color. Every risk band,
  /// confirmation sheet, and pill must resolve through this —
  /// never a literal Color keyed off risk elsewhere in the app.
  Color forRisk(RiskLevel r) => switch (r) {
        RiskLevel.read => dim,
        RiskLevel.mutate => amber,
        RiskLevel.destructive => red,
      };

  /// Machine state — green/amber/red/gray. Independent of [forRisk].
  Color forHealth(HealthStatus s) => switch (s) {
        HealthStatus.healthy => green,
        HealthStatus.warning => amber,
        HealthStatus.failed => red,
        HealthStatus.unknown => dim,
      };

  @override
  KelolaColors copyWith() => this;

  @override
  KelolaColors lerp(ThemeExtension<KelolaColors>? other, double t) => this;
}

class KelolaRadii {
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

class KelolaType {
  // Display: anything a human named — host names, unit names, titles.
  static TextStyle display({
    required Color color,
    double size = 16,
    FontWeight weight = FontWeight.w600,
  }) =>
      TextStyle(
        fontFamily: 'SpaceGrotesk',
        color: color,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.01 * size,
        height: 1.1,
      );

  // Body: prose, descriptions, dialog copy.
  static TextStyle body({
    required Color color,
    double size = 15,
    FontWeight weight = FontWeight.w400,
  }) =>
      TextStyle(
        fontFamily: 'IBMPlexSans',
        color: color,
        fontSize: size,
        fontWeight: weight,
        height: 1.55,
      );

  // Mono: ANYTHING THE SERVER PRODUCED. Commands, log lines,
  // timestamps, exit codes, paths, PIDs. This is the rule that
  // gives the whole app its "what's mine vs what's the machine's"
  // legibility — do not skip it for convenience.
  static TextStyle mono({
    required Color color,
    double size = 11,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        fontFamily: 'IBMPlexMono',
        color: color,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: 1.7,
      );
}

ThemeData buildKelolaDarkTheme() {
  const c = KelolaColors.dark;
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: c.ink,
    fontFamily: 'IBMPlexSans',
    extensions: const [c],
    colorScheme: ColorScheme.dark(
      surface: c.surface,
      primary: c.amber,
      error: c.red,
      onSurface: c.text,
    ),
    dividerColor: c.line,
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) => const Icon(Icons.arrow_back, size: 22),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: c.surface,
      titleTextStyle: KelolaType.display(color: c.text, size: 17),
      contentTextStyle: KelolaType.body(color: c.muted, size: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KelolaRadii.md),
        side: BorderSide(color: c.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface2,
      contentTextStyle: KelolaType.body(color: c.text, size: 13),
      actionTextColor: c.amber,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KelolaRadii.md),
        side: BorderSide(color: c.line),
      ),
    ),
  );
}

extension KelolaThemeContext on BuildContext {
  KelolaColors get kc => Theme.of(this).extension<KelolaColors>()!;
}
