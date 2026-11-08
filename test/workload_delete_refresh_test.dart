import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deleting from detail reloads the list', () {
    final detail = File(
      'lib/presentation/screens/workload_detail_screen.dart',
    ).readAsStringSync();
    expect(detail, contains('Navigator.of(context).pop(workloadDeleted)'));

    final list = File(
      'lib/presentation/screens/workloads_screen.dart',
    ).readAsStringSync();
    expect(list, contains('if (deleted == workloadDeleted && mounted)'));
  });
}
