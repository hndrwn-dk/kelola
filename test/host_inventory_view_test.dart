import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_inventory_view.dart';
import 'package:kelola/domain/hosts/os_icon_kind.dart';

Host _host({
  required String alias,
  HostAttention attention = HostAttention.unknown,
  int? failedUnitCount,
  int? diskRootPercent,
  DateTime? attentionAt,
  String? osId,
}) {
  return Host(
    id: alias,
    alias: alias,
    address: '10.0.0.1',
    port: 22,
    username: 'hendra',
    keyAlias: 'kelola-user',
    attention: attention,
    failedUnitCount: failedUnitCount,
    diskRootPercent: diskRootPercent,
    attentionAt: attentionAt,
    osId: osId,
  );
}

void main() {
  final now = DateTime.utc(2026, 9, 2, 8);

  test('groups never-opened and stale hosts as not checked', () {
    final neverOpened = _host(alias: 'ub');
    final staleHealthy = _host(
      alias: 'old',
      attention: HostAttention.healthy,
      failedUnitCount: 0,
      diskRootPercent: 40,
      attentionAt: now.subtract(const Duration(minutes: 16)),
    );
    final freshFailed = _host(
      alias: 'nas-01',
      attention: HostAttention.failedUnits,
      failedUnitCount: 2,
      diskRootPercent: 91,
      attentionAt: now.subtract(const Duration(minutes: 4)),
    );
    final freshHealthy = _host(
      alias: 'db',
      attention: HostAttention.healthy,
      failedUnitCount: 0,
      diskRootPercent: 40,
      attentionAt: now.subtract(const Duration(minutes: 2)),
    );
    final down = _host(
      alias: 'edge',
      attention: HostAttention.unreachable,
      attentionAt: now.subtract(const Duration(minutes: 1)),
    );

    final view = HostInventoryView.build(
      [neverOpened, staleHealthy, freshFailed, freshHealthy, down],
      now: now,
    );

    expect(view.needsAttention.map((h) => h.alias), ['nas-01', 'edge']);
    expect(view.healthy.map((h) => h.alias), ['db']);
    expect(view.notChecked.map((h) => h.alias), ['ub', 'old']);
  });

  test('summary strip counts hosts, healthy, and not checked', () {
    final view = HostInventoryView.build(
      [
        _host(alias: 'ub'),
        _host(alias: 'wsl'),
        _host(
          alias: 'db',
          attention: HostAttention.healthy,
          attentionAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      now: now,
    );
    expect(view.summary, '3 hosts · 1 healthy · 2 not checked');
  });

  test('summary includes needs attention when any host is in that bucket', () {
    final view = HostInventoryView.build(
      [
        _host(
          alias: 'nas-01',
          attention: HostAttention.failedUnits,
          failedUnitCount: 2,
          attentionAt: now,
        ),
        _host(
          alias: 'db',
          attention: HostAttention.healthy,
          attentionAt: now,
        ),
      ],
      now: now,
    );
    expect(view.summary, '2 hosts · 1 needs attention · 1 healthy');
  });

  test('inventory detail metrics moved to Fleet; Hosts keep pill only', () {
    final fresh = _host(
      alias: 'nas-01',
      attention: HostAttention.failedUnits,
      failedUnitCount: 2,
      diskRootPercent: 91,
      attentionAt: now.subtract(const Duration(minutes: 4)),
    );
    final stale = _host(
      alias: 'web',
      attention: HostAttention.failedUnits,
      failedUnitCount: 2,
      diskRootPercent: 91,
      attentionAt: now.subtract(const Duration(minutes: 16)),
    );
    expect(fresh.isAttentionStale(now: now), isFalse);
    expect(hostInventoryDetail(fresh, now: now), isNull);
    expect(stale.isAttentionStale(now: now), isTrue);
    expect(hostInventoryDetail(stale, now: now), isNull);
    expect(hostInventoryDetail(_host(alias: 'ub'), now: now), isNull);
  });

  test('collapses healthy and not-checked groups only when they exceed 8', () {
    expect(collapseInventoryGroup(HostInventoryBucket.healthy, 8), isFalse);
    expect(collapseInventoryGroup(HostInventoryBucket.healthy, 9), isTrue);
    expect(collapseInventoryGroup(HostInventoryBucket.notChecked, 8), isFalse);
    expect(collapseInventoryGroup(HostInventoryBucket.notChecked, 9), isTrue);
    expect(
      collapseInventoryGroup(HostInventoryBucket.needsAttention, 20),
      isFalse,
    );
  });

  test('os icon kind maps distro ids and falls back to generic linux', () {
    expect(osIconKind('ubuntu'), OsIconKind.ubuntu);
    expect(osIconKind('debian'), OsIconKind.debian);
    expect(osIconKind('fedora'), OsIconKind.fedora);
    expect(osIconKind('alpine'), OsIconKind.alpine);
    expect(osIconKind('arch'), OsIconKind.arch);
    expect(osIconKind('rhel'), OsIconKind.rhel);
    expect(osIconKind('centos'), OsIconKind.rhel);
    expect(osIconKind('rocky'), OsIconKind.rhel);
    expect(osIconKind('almalinux'), OsIconKind.rhel);
    expect(osIconKind(null), OsIconKind.linux);
    expect(osIconKind(''), OsIconKind.linux);
    expect(osIconKind('opensuse'), OsIconKind.linux);
  });
}
