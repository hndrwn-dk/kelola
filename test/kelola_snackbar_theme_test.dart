import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';

void main() {
  test('snackbar is surface2 on text, not Material inverse white', () {
    final theme = buildKelolaDarkTheme();
    expect(theme.snackBarTheme.backgroundColor, KelolaColors.dark.surface2);
    expect(theme.snackBarTheme.contentTextStyle?.color, KelolaColors.dark.text);
    expect(
      theme.snackBarTheme.backgroundColor,
      isNot(KelolaColors.dark.text),
    );
  });
}
