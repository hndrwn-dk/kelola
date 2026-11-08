import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

Future<TextField> _field(WidgetTester tester, KelolaInput input) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildKelolaDarkTheme(),
      home: Scaffold(body: input),
    ),
  );
  return tester.widget<TextField>(find.byType(TextField));
}

void main() {
  testWidgets('prose keeps the keyboard helpers', (tester) async {
    final field = await _field(tester, const KelolaInput(label: 'Alias'));
    expect(field.autocorrect, isTrue);
    expect(field.enableSuggestions, isTrue);
  });

  for (final (name, input) in const [
    ('mono', KelolaInput(label: 'Template', mono: true)),
    ('plain', KelolaInput(label: 'Address', plain: true)),
  ]) {
    testWidgets('a $name field is left as typed', (tester) async {
      final field = await _field(tester, input);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.smartQuotesType, SmartQuotesType.disabled);
    });
  }

  test('every field a host reads turns correction off', () {
    const fields = {
      'lib/presentation/screens/workload_exec_sheet.dart': 1,
      'lib/presentation/screens/terminal_sheet.dart': 3,
      'lib/presentation/screens/journal_screen.dart': 1,
      'lib/presentation/screens/processes_screen.dart': 1,
      'lib/presentation/screens/units_screen.dart': 1,
      'lib/presentation/screens/containers_screen.dart': 1,
      'lib/presentation/screens/workloads_screen.dart': 1,
      'lib/presentation/screens/file_editor_screen.dart': 1,
      'lib/presentation/screens/workload_yaml_screen.dart': 1,
      'lib/presentation/widgets/kelola_chrome.dart': 1,
    };
    fields.forEach((path, count) {
      final src = File(path).readAsStringSync();
      expect(
        'autocorrect: false'.allMatches(src).length,
        count,
        reason: path,
      );
      expect(
        'smartQuotesType: SmartQuotesType.disabled'.allMatches(src).length,
        count,
        reason: path,
      );
    });
  });

  test('a new pod command clears the last result', () {
    final src = File(
      'lib/presentation/screens/workload_exec_sheet.dart',
    ).readAsStringSync();
    expect(src, contains("_out = '';"));
  });

  test('a finished terminal session says so', () {
    final src = File(
      'lib/presentation/screens/pty_terminal_screen.dart',
    ).readAsStringSync();
    expect(src, contains('onDone:'));
    expect(src, contains('ptySessionEndedCopy'));
  });

  test('a timeout does not ask for a pull that sheets cannot do', () {
    expect(
      File('lib/domain/exceptions.dart').readAsStringSync(),
      isNot(contains('Pull to try again')),
    );
  });
}
