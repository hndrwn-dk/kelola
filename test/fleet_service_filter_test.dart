import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/data/fleet/fleet_probe_selection_store.dart';
import 'package:kelola/data/services/service_lens_store.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';
import 'package:kelola/presentation/fleet/fleet_service_filter.dart';
import 'package:kelola/presentation/screens/fleet_screen.dart';
import 'package:kelola/providers.dart';

ServiceDetection det(List<ServiceId> ids) => ServiceDetection(
      services: [
        for (final id in ids)
          DetectedService(id: id, state: ServiceState.running),
      ],
      listeningPorts: const [],
      readAt: DateTime.utc(2026, 11, 1),
    );

class _Locked implements Entitlement {
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  void dispose() {}
  @override
  void initialize() {}
  @override
  bool isUnlocked(ProFeature feature) => false;
  @override
  Future<ProPurchaseResult> purchase() async => ProPurchaseResult.unavailable;
  @override
  Future<ProPurchaseResult> restore() async => ProPurchaseResult.unavailable;
  @override
  String get sourceLabel => 'std';
  @override
  String? get priceLabel => null;
}

void main() {
  test('counts only hosts in the fleet', () {
    final cache = {
      'a': det([ServiceId.nginx, ServiceId.postgres]),
      'b': det([ServiceId.nginx]),
      'gone': det([ServiceId.nginx, ServiceId.apache]),
    };
    final counts = serviceCounts(cache, ['a', 'b', 'c']);
    expect(counts, {ServiceId.nginx: 2, ServiceId.postgres: 1});
    expect(counts.keys.toList(), [ServiceId.nginx, ServiceId.postgres]);
  });

  test("pill label 'nginx 3'", () {
    expect(servicePillLabel(ServiceId.nginx, 3), 'nginx 3');
    expect(servicePillLabel(ServiceId.postgres, 1), 'postgres 1');
    expect(servicePillLabel(ServiceId.apache, 1), 'apache 1');
  });

  test('matchesService null rules', () {
    expect(matchesService(null, ServiceId.nginx), isFalse);
    expect(matchesService(null, null), isTrue);
    expect(matchesService(det([ServiceId.nginx]), null), isTrue);
    expect(matchesService(det([ServiceId.nginx]), ServiceId.apache), isFalse);
  });

  group('fleet screen', () {
    late KelolaDatabase db;
    late HostRepository repo;
    late ServiceLensStore store;

    setUp(() async {
      db = KelolaDatabase.memory();
      repo = HostRepository(db);
      store = ServiceLensStore.memory();
      await repo.saveDeviceKey(blobB64: 'YQ==', backend: 'test');
    });
    tearDown(() async => db.close());

    Future<Host> addHost(String alias, {List<String> tags = const []}) async {
      final h = await repo.insert(
        alias: alias,
        address: '10.0.0.1',
        port: 22,
        username: 'ops',
      );
      if (tags.isNotEmpty) {
        await repo.setHostTags(h.id, tags);
      }
      return h;
    }

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            hostRepositoryProvider.overrideWithValue(repo),
            entitlementProvider.overrideWithValue(_Locked()),
            serviceLensStoreProvider.overrideWith((ref) async => store),
            fleetProbeSelectionStoreProvider.overrideWith(
              (ref) async => FleetProbeSelectionStore.memory(),
            ),
          ],
          child: const KelolaApp(home: FleetScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('AND with tag filter', (tester) async {
      await tester.runAsync(() async {
        final a = await addHost('alpha', tags: ['prod']);
        final b = await addHost('bravo', tags: ['dev']);
        final c = await addHost('charlie', tags: ['prod']);
        await store.write(a.id, det([ServiceId.nginx]));
        await store.write(b.id, det([ServiceId.nginx]));
        await store.write(c.id, det([ServiceId.postgres]));
      });
      await pump(tester);

      expect(find.text('NGINX 2'), findsOneWidget);
      expect(find.text('POSTGRES 1'), findsOneWidget);
      await tester.tap(find.text('NGINX 2'));
      await tester.pump();
      expect(find.text('alpha'), findsWidgets);
      expect(find.text('bravo'), findsWidgets);
      expect(find.text('charlie'), findsNothing);

      await tester.tap(find.text('PROD'));
      await tester.pump();
      expect(find.text('alpha'), findsWidgets);
      expect(find.text('bravo'), findsNothing);

      // Tapping the selected pill clears the service filter only.
      await tester.tap(find.text('NGINX 2'));
      await tester.pump();
      expect(find.text('charlie'), findsWidgets);
      expect(find.text('bravo'), findsNothing);
      await done(tester);
    });

    testWidgets("empty copy 'No hosts with this service.'", (tester) async {
      await tester.runAsync(() async {
        final a = await addHost('alpha', tags: ['prod']);
        final b = await addHost('bravo', tags: ['dev']);
        await store.write(a.id, det([ServiceId.nginx]));
        await store.write(b.id, det([ServiceId.postgres]));
      });
      await pump(tester);

      await tester.tap(find.text('DEV'));
      await tester.pump();
      await tester.tap(find.text('NGINX 1'));
      await tester.pump();
      expect(find.text('No hosts with this service.'), findsOneWidget);
      await done(tester);
    });

    testWidgets(
        "hosts without cache excluded and hint 'detected on open' shown",
        (tester) async {
      await tester.runAsync(() async {
        final a = await addHost('alpha');
        await addHost('bravo');
        await store.write(a.id, det([ServiceId.nginx]));
      });
      await pump(tester);

      expect(find.text('NGINX 1'), findsOneWidget);
      expect(find.text('detected on open'), findsOneWidget);
      await tester.tap(find.text('NGINX 1'));
      await tester.pump();
      expect(find.text('alpha'), findsWidgets);
      expect(find.text('bravo'), findsNothing);
      await done(tester);
    });

    testWidgets('no cache at all shows no pills and no hint', (tester) async {
      await tester.runAsync(() => addHost('alpha'));
      await pump(tester);
      expect(find.text('detected on open'), findsNothing);
      expect(find.byType(FilterPill), findsNothing);
      await done(tester);
    });
  });
}
