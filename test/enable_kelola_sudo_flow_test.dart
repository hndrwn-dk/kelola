import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enable sudo flow has no group picker; always applies default set', () {
    final src = File(
      'lib/presentation/widgets/enable_kelola_sudo_flow.dart',
    ).readAsStringSync();
    expect(src, isNot(contains('FilterPill')));
    expect(src, isNot(contains('preselected')));
    expect(src, contains('defaultKelolaSudoersGroups'));
    expect(src, contains('Review and apply'));
  });
}
