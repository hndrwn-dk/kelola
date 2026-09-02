import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/domain/units/unit_detail_view.dart';

UnitDetail _detail(Map<String, String> properties) {
  return UnitDetail(
    name: properties['Id'] ?? 'unit.service',
    properties: properties,
    logs: '',
    dependencies: '',
  );
}

void main() {
  final now = DateTime.utc(2026, 9, 2, 8);

  test('failed unit with ExecMainStatus 1 matches S09 kicker', () {
    final d = _detail({
      'ActiveState': 'failed',
      'ExecMainStatus': '1',
      'ExecMainCode': '1',
      'Result': 'exit-code',
      'ActiveEnterTimestamp': 'Sun 2026-08-30 09:12:04 UTC',
    });
    expect(unitDetailKicker(d, now: now), 'FAILED · EXIT 1');
    expect(unitDetailMeta(d, now: now), 'failed · exit 1');
  });

  test('ExecMainStatus 0 falls back to Result, never exit 0', () {
    final timeout = _detail({
      'ActiveState': 'failed',
      'ExecMainStatus': '0',
      'ExecMainCode': '1',
      'Result': 'timeout',
    });
    expect(unitDetailMeta(timeout, now: now), 'failed · timeout');
    expect(unitDetailKicker(timeout, now: now), 'FAILED · TIMEOUT');

    final startup = _detail({
      'ActiveState': 'failed',
      'ExecMainStatus': '0',
      'Result': 'exit-code',
    });
    expect(unitDetailMeta(startup, now: now), 'failed · exit-code');
  });

  test('signal death uses ExecMainCode, not exit N', () {
    final d = _detail({
      'ActiveState': 'failed',
      'ExecMainStatus': '9',
      'ExecMainCode': '2',
      'Result': 'signal',
    });
    expect(unitDetailMeta(d, now: now), 'failed · signal 9');
  });

  test('failed units never show ActiveEnterTimestamp as uptime', () {
    final d = _detail({
      'ActiveState': 'failed',
      'ExecMainStatus': '1',
      'Result': 'exit-code',
      'ActiveEnterTimestamp': 'Sun 2026-08-30 09:12:04 UTC',
    });
    expect(unitUptimeLabel(d, now: now), isNull);
    expect(unitDetailMeta(d, now: now), 'failed · exit 1');
  });

  test('active unit uptime comes from ActiveEnterTimestamp', () {
    final d = _detail({
      'ActiveState': 'active',
      'SubState': 'running',
      'ActiveEnterTimestamp': 'Sun 2026-07-17 08:00:00 UTC',
    });
    expect(unitUptimeLabel(d, now: now), '47d');
    expect(unitDetailMeta(d, now: now), 'active · 47d');
    expect(unitDetailKicker(d, now: now), 'ACTIVE · 47D');
  });
}
