import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/db/tunnel_repository.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/service_forward.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:kelola/presentation/screens/k8s_resource_detail_screen.dart';
import 'package:kelola/providers.dart';

import 'support/fakes.dart';

const _svc = K8sService(
  namespace: 'shop',
  name: 'web',
  type: 'ClusterIP',
  clusterIp: '10.43.0.11',
  ports: '80/TCP, 53/UDP, 443/TCP',
  hasSelector: true,
  portList: [
    K8sServicePort(port: 80),
    K8sServicePort(port: 53, protocol: 'UDP'),
    K8sServicePort(port: 443),
  ],
);

void main() {
  group('domain', () {
    test('only TCP ports forward; ExternalName forwards nothing', () {
      expect(forwardablePorts(_svc).map((p) => p.port), [80, 443]);
      expect(
        forwardablePorts(
          const K8sService(
            namespace: 'a',
            name: 'ext',
            type: 'ExternalName',
            clusterIp: '',
            ports: '80/TCP',
            hasSelector: false,
            portList: [K8sServicePort(port: 80)],
          ),
        ),
        isEmpty,
      );
    });

    test('target uses svc resource, namespace path; reuses a saved one', () {
      final t = serviceForwardTarget(
        hostId: 'h1',
        service: _svc,
        port: _svc.portList.first,
        saved: const [],
        newId: () => 'new-id',
      );
      expect(t.id, 'new-id');
      expect(t.kind, TunnelKind.kubectl);
      expect(t.remoteHost, 'svc/web');
      expect(t.remotePort, 80);
      expect(t.path, 'shop');
      expect(t.label, 'web:80');

      final again = serviceForwardTarget(
        hostId: 'h1',
        service: _svc,
        port: _svc.portList.first,
        saved: [t],
        newId: () => 'other-id',
      );
      expect(again.id, 'new-id');

      final otherPort = serviceForwardTarget(
        hostId: 'h1',
        service: _svc,
        port: _svc.portList.last,
        saved: [t],
        newId: () => 'third-id',
      );
      expect(otherPort.id, 'third-id');
    });
  });

  group('service detail', () {
    late KelolaDatabase db;
    late HostRepository repo;
    late Host host;

    setUp(() async {
      db = KelolaDatabase.memory();
      repo = HostRepository(db);
      host = await repo.insert(
        alias: 'rocky-lab',
        address: '192.168.1.40',
        port: 22,
        username: 'hendra',
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<List<String>> pump(
      WidgetTester tester, {
      required bool unlocked,
    }) async {
      final opened = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            hostRepositoryProvider.overrideWithValue(repo),
            entitlementProvider.overrideWithValue(
              FixedEntitlement(unlocked: unlocked),
            ),
          ],
          child: KelolaApp(
            home: K8sServiceDetailScreen(
              snapshot: K8sSnapshot(hostId: host.id, workloads: const []),
              service: _svc,
              openTunnels: (_, hostId) => opened.add(hostId),
            ),
          ),
        ),
      );
      await tester.pump();
      return opened;
    }

    testWidgets('unlocked: forward saves one kubectl target, then reuses it',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final opened = await pump(tester, unlocked: true);
      expect(find.text('Forward 80/TCP'), findsOneWidget);
      expect(find.text('Forward 443/TCP'), findsOneWidget);
      expect(find.text('Forward 53/TCP'), findsNothing);

      final tunnels = TunnelRepository(db);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Forward 80/TCP'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      final saved = await tester.runAsync(() => tunnels.listForHost(host.id));
      expect(saved, hasLength(1));
      expect(saved!.single.remoteHost, 'svc/web');
      expect(saved.single.path, 'shop');
      expect(opened, [host.id, host.id]);
    });

    testWidgets('locked: forward shows the explainer and saves nothing',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final opened = await pump(tester, unlocked: false);
      await tester.tap(find.text('Forward 80/TCP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('keeps tunnels locked'), findsOneWidget);
      final saved = await tester.runAsync(
        () => TunnelRepository(db).listForHost(host.id),
      );
      expect(saved, isEmpty);
      expect(opened, isEmpty);
    });
  });
}

