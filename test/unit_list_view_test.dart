import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/domain/units/unit_list_view.dart';

ServiceUnit _unit({
  required String name,
  String active = 'active',
  String sub = 'running',
  String description = '',
  String? unitFileState,
}) {
  return ServiceUnit(
    name: name,
    description: description,
    load: 'loaded',
    active: active,
    sub: sub,
    unitFileState: unitFileState,
  );
}

void main() {
  final nginx = _unit(
    name: 'nginx.service',
    active: 'failed',
    sub: 'failed',
    unitFileState: 'enabled',
  );
  final borg = _unit(
    name: 'borgmatic.service',
    active: 'failed',
    sub: 'failed',
    unitFileState: 'enabled',
  );
  final sshd = _unit(
    name: 'sshd.service',
    unitFileState: 'enabled',
  );
  final docker = _unit(
    name: 'docker.service',
    unitFileState: 'enabled',
  );
  final leftover = _unit(
    name: 'apt-daily.service',
    active: 'inactive',
    sub: 'dead',
    unitFileState: 'disabled',
  );
  final all = [nginx, borg, sshd, docker, leftover];
  final healthy = [sshd, docker, leftover];

  test('FAILED is a pure filter: only ActiveState failed, no running slab', () {
    final view = UnitListView.build(all, UnitListFilter.failed);
    expect(view.failed.map((u) => u.name), ['nginx.service', 'borgmatic.service']);
    expect(view.running, isEmpty);
    expect(view.other, isEmpty);
    expect(view.showRunningSlab, isFalse);
  });

  test('FAILED with zero failed units is empty: no running slab', () {
    final view = UnitListView.build(healthy, UnitListFilter.failed);
    expect(view.isEmpty, isTrue);
    expect(view.failed, isEmpty);
    expect(view.running, isEmpty);
    expect(view.other, isEmpty);
    expect(view.showRunningSlab, isFalse);
  });

  test('FAILED empty copy names active count', () {
    final counts = UnitListCounts.from(healthy);
    expect(
      unitListEmptyCopy(UnitListFilter.failed, activeCount: counts.running),
      'No failed units · 2 active',
    );
  });

  test('RUNNING is a pure filter: active non-failed only', () {
    final view = UnitListView.build(all, UnitListFilter.running);
    expect(view.failed, isEmpty);
    expect(view.running.map((u) => u.name), ['sshd.service', 'docker.service']);
    expect(view.other, isEmpty);
    expect(view.showRunningSlab, isFalse);
  });

  test('ENABLED is a pure filter: unit-file enabled only', () {
    final view = UnitListView.build(all, UnitListFilter.enabled);
    expect(view.failed.map((u) => u.name), ['nginx.service', 'borgmatic.service']);
    expect(view.running.map((u) => u.name), ['sshd.service', 'docker.service']);
    expect(view.other, isEmpty);
    expect(view.failed.length + view.running.length + view.other.length, 4);
  });

  test('ALL is the only filter that applies failed-first grouping', () {
    final view = UnitListView.build(all, UnitListFilter.all);
    expect(view.failed.map((u) => u.name), ['nginx.service', 'borgmatic.service']);
    expect(view.running.map((u) => u.name), ['sshd.service', 'docker.service']);
    expect(view.other.single.name, 'apt-daily.service');
    expect(view.showRunningSlab, isTrue);
    expect(view.showOtherSlab, isTrue);

    final failedOnly = UnitListView.build(all, UnitListFilter.failed);
    expect(failedOnly.showRunningSlab, isFalse);
    expect(failedOnly.running, isEmpty);
  });

  test('chip counts are inventory totals', () {
    final mixed = UnitListCounts.from(all);
    expect(mixed.failed, 2);
    expect(mixed.running, 2);
    expect(mixed.enabled, 4);
    expect(mixed.all, 5);
    expect(unitListChipLabel(UnitListFilter.failed, mixed), 'Failed 2');
    expect(unitListChipLabel(UnitListFilter.running, mixed), 'Running 2');
    expect(unitListChipLabel(UnitListFilter.enabled, mixed), 'Enabled 4');
    expect(unitListChipLabel(UnitListFilter.all, mixed), 'All 5');

    final noneFailed = UnitListCounts.from(healthy);
    expect(noneFailed.failed, 0);
    expect(unitListChipLabel(UnitListFilter.failed, noneFailed), 'Failed 0');
    expect(unitListChipLabel(UnitListFilter.running, noneFailed), 'Running 2');
    expect(unitListChipLabel(UnitListFilter.enabled, noneFailed), 'Enabled 2');
    expect(unitListChipLabel(UnitListFilter.all, noneFailed), 'All 3');
  });

  test('kicker always includes real failed count', () {
    expect(unitListKicker(UnitListCounts.from(all)), '5 UNITS · 2 FAILED');
    expect(unitListKicker(UnitListCounts.from(healthy)), '3 UNITS · 0 FAILED');
  });

  test('default landing is FAILED if any failed, else ALL', () {
    expect(defaultUnitListFilter(all), UnitListFilter.failed);
    expect(defaultUnitListFilter(healthy), UnitListFilter.all);
    expect(defaultUnitListFilter(const []), UnitListFilter.all);
  });

  test('query filters name and description', () {
    final named = UnitListView.build(all, UnitListFilter.all, query: 'nginx');
    expect(named.failed.single.name, 'nginx.service');
    expect(named.running, isEmpty);

    final described = UnitListView.build(
      [
        _unit(name: 'web.service', description: 'nginx reverse proxy'),
        sshd,
      ],
      UnitListFilter.all,
      query: 'reverse',
    );
    expect(described.running.single.name, 'web.service');
  });

  test('query miss uses generic empty copy', () {
    expect(
      unitListEmptyCopy(
        UnitListFilter.failed,
        activeCount: 2,
        query: 'zzz',
      ),
      'No units match.',
    );
  });

  test('meta is active · sub without inventing exit codes', () {
    expect(unitListMeta(nginx), 'failed');
    expect(unitListMeta(sshd), 'active · running');
    expect(
      unitListMeta(
        _unit(name: 'x.service', active: 'failed', sub: 'exited'),
      ),
      'failed · exited',
    );
  });
}
