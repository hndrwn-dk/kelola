import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journal receive log never prints a raw stdout prefix', () {
    final src = File('lib/domain/probes/journal_probe.dart').readAsStringSync();
    expect(src, contains('kDebugMode'));
    expect(src, isNot(contains('prefix=')));
    expect(src, isNot(contains('jsonEncode(prefix)')));
  });
}
