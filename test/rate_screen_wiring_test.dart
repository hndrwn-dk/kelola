import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/metrics/rate_sample.dart';

void main() {
  test('dashboard probe never samples diskstats or netdev', () {
    final src =
        File('lib/domain/probes/dashboard_probe.dart').readAsStringSync();
    expect(src, isNot(contains('diskstats')));
    expect(src, isNot(contains('net/dev')));
    expect(src, isNot(contains('kRateSampleInterval')));
  });

  test('disk and network screens sample only while open', () {
    final disk =
        File('lib/presentation/screens/disk_screen.dart').readAsStringSync();
    final net =
        File('lib/presentation/screens/network_screen.dart').readAsStringSync();
    expect(disk, contains('kRateSampleInterval'));
    expect(disk, contains('Measuring'));
    expect(disk, contains('Could not finish disk rate sample'));
    expect(net, contains('kRateSampleInterval'));
    expect(net, contains('Measuring'));
    expect(net, contains('Could not finish network rate sample'));
    expect(kRateSampleInterval, const Duration(seconds: 1));
  });
}
