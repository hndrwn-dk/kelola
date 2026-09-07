import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/fleet/fleet_actions.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';

FleetHostHealth sample({
  bool reachable = true,
  double load1 = 0.2,
  int? nprocCores = 4,
  int mem = 40,
  int disk = 10,
  List<String> highDisk = const [],
  int failed = 0,
  int pending = 0,
  int security = 0,
  int containersDown = 0,
  int containersUnhealthy = 0,
  bool reboot = false,
}) {
  return FleetHostHealth(
    hostId: 'h1',
    alias: 'web',
    reachable: reachable,
    load1: load1,
    nprocCores: nprocCores,
    memPercent: mem,
    diskRootPercent: disk,
    highDiskMounts: highDisk,
    failedUnitCount: failed,
    pendingUpdates: pending,
    securityUpdates: security,
    containersDown: containersDown,
    containersUnhealthy: containersUnhealthy,
    uptime: const Duration(hours: 1),
    rebootRequired: reboot,
    fetchedAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  final cases = <FleetHostHealth>[
    sample(),
    sample(reachable: false),
    sample(failed: 2),
    sample(containersDown: 1),
    sample(disk: 95),
    sample(highDisk: const ['/var:91%']),
    sample(load1: 4.06, nprocCores: 1),
    sample(load1: 5.0, nprocCores: null),
    sample(mem: 95),
    sample(security: 3),
    sample(pending: 4),
    sample(reboot: true),
    sample(failed: 1, load1: 8, nprocCores: 1, disk: 99, security: 2),
  ];

  test('assessFleetHost: healthy iff issues empty (property)', () {
    for (final h in cases) {
      final a = assessFleetHost(h);
      expect(
        a.severity == FleetSeverity.healthy,
        a.issues.isEmpty,
        reason: '${h.alias} sev=${a.severity} issues=${a.issues.length}',
      );
      expect(
        a.severity != FleetSeverity.healthy,
        a.issues.isNotEmpty,
        reason: '${h.alias} sev=${a.severity} issues=${a.issues.length}',
      );
    }
  });

  test('load High produces failed tile health and a load issue', () {
    final a = assessFleetHost(sample(load1: 4.06, nprocCores: 1));
    expect(a.severity, FleetSeverity.loadHigh);
    expect(a.tileHealth, FleetTileHealth.failed);
    expect(a.issues, isNotEmpty);
    expect(a.issues.first.kind, FleetIssueKind.loadHigh);
  });

  test('formatFleetLoad identical for tile and sheet (>100% and raw)', () {
    expect(formatFleetLoad(4.06, 1), '406%');
    expect(formatFleetLoad(3.82, 1), '382%');
    expect(formatFleetLoad(1.14, 1), '114%');
    expect(formatFleetLoad(0.2, 4), '5%');
  });

  test('formatFleetLoad is raw loadavg when cores omitted', () {
    expect(formatFleetLoad(3.82, null), '3.82');
    expect(formatFleetLoad(4.06, 0), '4.06');
    expect(formatFleetLoad(4.06, -1), '4.06');
    expect(formatFleetLoad(3.82, null), isNot(contains('%')));
  });

  test('tileMetrics load matches formatFleetLoad for same sample', () {
    final withCores = sample(load1: 4.06, nprocCores: 1);
    final noCores = sample(load1: 3.82, nprocCores: null);
    expect(
      withCores.tileMetrics().singleWhere((m) => m.label == 'load').value,
      formatFleetLoad(withCores.load1, withCores.nprocCores),
    );
    expect(
      noCores.tileMetrics().singleWhere((m) => m.label == 'load').value,
      formatFleetLoad(noCores.load1, noCores.nprocCores),
    );
  });

  test('same sample: sheet headline load/mem match tile metrics', () {
    final h = sample(load1: 4.06, nprocCores: 1, mem: 57);
    final tile = h.tileMetrics();
    expect(
      tile.singleWhere((m) => m.label == 'load').value,
      formatFleetLoad(h.load1, h.nprocCores),
    );
    expect(tile.singleWhere((m) => m.label == 'mem').value, '${h.memPercent}%');
    expect(formatFleetLoad(h.load1, h.nprocCores), '406%');
    expect(h.memPercent, 57);
  });

  test('issue priority: unreachable before failed units before load', () {
    final a = assessFleetHost(
      sample(reachable: false, failed: 2, load1: 9, nprocCores: 1),
    );
    expect(a.severity, FleetSeverity.unreachable);
    expect(a.issues.first.kind, FleetIssueKind.unreachable);

    final b = assessFleetHost(sample(failed: 1, load1: 9, nprocCores: 1));
    expect(b.severity, FleetSeverity.failedUnits);
    expect(b.issues.map((i) => i.kind).toList(), [
      FleetIssueKind.failedUnit,
      FleetIssueKind.loadHigh,
    ]);
  });

  test('fleetIssues delegates to assessFleetHost', () {
    final h = sample(load1: 4.06, nprocCores: 1);
    expect(fleetIssues(h).map((i) => i.kind), [
      FleetIssueKind.loadHigh,
    ]);
  });

  test('failed units map to failedUnits attention for inventory', () {
    expect(
      attentionFromFleetHealth(sample(failed: 1)),
      HostAttention.failedUnits,
    );
    expect(
      attentionFromFleetHealth(sample(failed: 0)),
      HostAttention.healthy,
    );
  });
}
