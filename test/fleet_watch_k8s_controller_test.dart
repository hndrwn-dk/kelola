import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/fleet/fleet_watch_bridge.dart';
import 'package:kelola/data/fleet/fleet_watch_runner.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/probes/fleet_k8s_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';
import 'package:kelola/presentation/fleet/fleet_watch_controller.dart';

import 'support/fakes.dart';

/// M32 spec Tests: "a k8s probe failure keeps the host reachable", checked
/// through the real fleet watch tick, not just the summary.
void main() {
  test('k8s read failing keeps the host reachable and pages nobody', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'k3s-lab',
      address: '10.0.0.5',
      port: 22,
      username: 'ops',
    );
    await repo.saveFacts(
      host.id,
      HostFacts.undiscovered.copyWith(runtimes: const ['k3s']),
    );
    await repo.setFleetWatchEnabled(true);
    final pool = _FleetPool(repository: repo);
    final bridge = _Bridge();
    final controller = FleetWatchController(
      hosts: repo,
      pool: pool,
      bridge: bridge,
      widgetBridge: _Widget(),
      entitlement: FixedEntitlement(unlocked: true),
      selectedHostIds: () async => null,
    );

    await controller.maybeTick(force: true);

    expect(pool.kinds, [FleetHealthProbe, FleetClusterProbe]);
    expect(pool.scopes, everyElement(ProbeScope.fleet));
    final cached = (await repo.loadFleetCacheByHost())[host.id]!;
    expect(cached.reachable, isTrue);
    expect(cached.k8s!.read, isFalse);
    expect(cached.k8s!.label, 'not readable');
    expect(bridge.notices, isEmpty);
  });
}

class _FleetPool extends SshSessionPool {
  _FleetPool({required super.repository})
      : super(
          signer: NoSshSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
        );

  final kinds = <Type>[];
  final scopes = <ProbeScope>[];

  @override
  Future<T> execute<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
    ProbeScope scope = ProbeScope.host,
    List<int>? stdinBytes,
  }) async {
    kinds.add(probe.runtimeType);
    scopes.add(scope);
    if (probe is FleetHealthProbe) {
      return FleetHostHealth(
        hostId: host.id,
        alias: host.alias,
        reachable: true,
        load1: 0.2,
        nprocCores: 4,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 11, 3),
      ) as T;
    }
    if (probe is FleetClusterProbe) {
      throw StateError('kubectl hung');
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

class _Bridge implements FleetWatchBridge {
  final notices = <FleetWatchNotice>[];

  @override
  Future<void> cancel() async {}

  @override
  Future<void> notify(FleetWatchNotice notice) async => notices.add(notice);

  @override
  Future<bool> requestPostNotifications() async => true;

  @override
  Future<void> schedule() async {}

  @override
  void setTickHandler(Future<void> Function()? handler) {}
}

class _Widget implements HomeWidgetBridge {
  @override
  Future<void> write(HomeWidgetSnapshot snap) async {}
}
