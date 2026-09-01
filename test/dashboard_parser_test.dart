import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/dashboard_parser.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';

void main() {
  test('parses dashboard batch from nas-01 fixture', () {
    final raw =
        File('test/fixtures/host_facts/dashboard_nas01.txt').readAsStringSync();
    final snap = const DashboardParser().parse(raw);
    expect(snap.uptime.inDays, 47);
    expect(snap.load1, 0.84);
    expect(snap.memUsedPercent, 61);
    expect(snap.diskRootPercent, 83);
    expect(snap.failedUnitCount, 2);
    expect(snap.failedUnitNames, ['nginx.service', 'borgmatic.service']);
    expect(snap.attention, HostAttentionFromSnapshot.failedUnits);
  });
}
