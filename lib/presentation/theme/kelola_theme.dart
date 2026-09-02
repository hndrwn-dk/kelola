import 'package:flutter/material.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';

@immutable
class KelolaColors extends ThemeExtension<KelolaColors> {
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
    required this.red,
    required this.green,
    required this.blue,
  });

  final Color ink;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color text;
  final Color muted;
  final Color dim;
  final Color amber;
  final Color red;
  final Color green;
  final Color blue;

  static const dark = KelolaColors(
    ink: Color(0xFF0D1117),
    surface: Color(0xFF161B22),
    surface2: Color(0xFF21262D),
    surface3: Color(0xFF30363D),
    line: Color(0x14FFFFFF),
    text: Color(0xFFE6EDF3),
    muted: Color(0xFF8B949E),
    dim: Color(0xFF6E7681),
    amber: Color(0xFFF0A02C),
    red: Color(0xFFE5484D),
    green: Color(0xFF3FB950),
    blue: Color(0xFF58A6FF),
  );

  static const hazardDark = Color(0xFF3A1416);
  static const onAmber = Color(0xFF1A1206);

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
    Color? surface3,
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
      surface3: surface3 ?? this.surface3,
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

class _KelolaFade extends PageTransitionsBuilder {
  const _KelolaFade();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    );
  }
}

ThemeData kelolaTheme() {
  const colors = KelolaColors.dark;
  const fade = _KelolaFade();
  final scheme = ColorScheme.dark(
    surface: colors.ink,
    primary: colors.amber,
    onPrimary: KelolaColors.onAmber,
    secondary: colors.muted,
    error: colors.red,
    onSurface: colors.text,
    outline: colors.line,
  );
  final body = TextTheme(
    bodyLarge: TextStyle(
      fontFamily: KelolaFonts.body,
      fontSize: 15,
      height: 1.45,
      color: colors.text,
    ),
    bodyMedium: TextStyle(
      fontFamily: KelolaFonts.body,
      fontSize: 14,
      height: 1.45,
      color: colors.text,
    ),
    bodySmall: TextStyle(
      fontFamily: KelolaFonts.body,
      fontSize: 12,
      height: 1.4,
      color: colors.muted,
    ),
    titleLarge: KelolaFonts.title(color: colors.text, size: 20),
    titleMedium: KelolaFonts.title(color: colors.text, size: 16),
    titleSmall: KelolaFonts.title(color: colors.text, size: 14),
    labelLarge: KelolaFonts.title(color: colors.text, size: 13),
    labelSmall: KelolaFonts.eyebrow(colors),
  );
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: colors.line),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: KelolaFonts.body,
    scaffoldBackgroundColor: colors.ink,
    canvasColor: colors.ink,
    extensions: const [colors],
    textTheme: body,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    highlightColor: colors.amber.withValues(alpha: 0.06),
    splashColor: Colors.transparent,
    hoverColor: colors.surface2,
    dividerColor: colors.line,
    dividerTheme: DividerThemeData(
      color: colors.line,
      thickness: 1,
      space: 1,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: fade,
        TargetPlatform.iOS: fade,
        TargetPlatform.windows: fade,
        TargetPlatform.linux: fade,
        TargetPlatform.macOS: fade,
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.ink,
      foregroundColor: colors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 4,
      toolbarHeight: 56,
      titleTextStyle: KelolaFonts.title(color: colors.text, size: 18),
      iconTheme: IconThemeData(color: colors.muted, size: 20),
      actionsIconTheme: IconThemeData(color: colors.muted, size: 20),
      shape: Border(bottom: BorderSide(color: colors.line)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.muted,
        highlightColor: colors.amber.withValues(alpha: 0.08),
        visualDensity: VisualDensity.compact,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.amber,
        foregroundColor: KelolaColors.onAmber,
        elevation: 0,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: KelolaFonts.title(size: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.text,
        side: BorderSide(color: colors.line),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: KelolaFonts.title(size: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.muted,
        textStyle: KelolaFonts.title(size: 13),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surface2,
      selectedColor: colors.surface2,
      side: BorderSide(color: colors.line),
      labelStyle: KelolaFonts.title(color: colors.text, size: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: const Color(0x66000000),
      textStyle: TextStyle(fontFamily: KelolaFonts.body, color: colors.text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.line),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: KelolaFonts.title(color: colors.text, size: 17),
      contentTextStyle: TextStyle(
        fontFamily: KelolaFonts.body,
        fontSize: 13,
        height: 1.55,
        color: colors.muted,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surface2,
      contentTextStyle: TextStyle(
        fontFamily: KelolaFonts.body,
        fontSize: 13,
        height: 1.4,
        color: colors.text,
      ),
      actionTextColor: colors.amber,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface2,
      hintStyle: KelolaFonts.machine(color: colors.dim, size: 13),
      labelStyle: KelolaFonts.machine(color: colors.dim, size: 11),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.amber.withValues(alpha: 0.7)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.amber,
      linearMinHeight: 1.5,
      linearTrackColor: colors.surface2,
      circularTrackColor: colors.surface2,
    ),
    listTileTheme: ListTileThemeData(
      tileColor: colors.surface,
      iconColor: colors.dim,
      textColor: colors.text,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.line),
      ),
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.line),
      ),
    ),
  );
}

String keyBackendLabel(String? backend) {
  switch (backend) {
    case 'strongbox':
      return 'StrongBox';
    case 'secureEnclave':
      return 'Secure Enclave';
    case 'tee':
      return 'TEE';
    case 'software':
      return 'software key';
    default:
      return 'this phone';
  }
}
