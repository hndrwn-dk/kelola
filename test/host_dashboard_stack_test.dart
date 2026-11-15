import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/k8s/cluster_kind_store.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/services/service_lens_store.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/service_detect_probe.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/web_lens_screen.dart';
import 'package:kelola/presentation/services/stack_section.dart';
import 'package:kelola/providers.dart';

const _nginx = DetectedService(
  id: ServiceId.nginx,
  state: ServiceState.running,
  unit: 'nginx.service',
  version: '1.24.0',
);
const _apache = DetectedService(
  id: ServiceId.apache,
  state: ServiceState.stopped,
  unit: 'apache2.service',
);
const _postgres = DetectedService(
  id: ServiceId.postgres,
  state: ServiceState.running,
  unit: 'postgresql.service',
  version: '16.2',
);

final _readAt = DateTime.utc(2026, 11, 10, 12);

ServiceDetection _detection(List<DetectedService> services, {DateTime? at}) =>
    ServiceDetection(
      services: services,
      listeningPorts: const [80],
      readAt: at ?? _readAt,
    );

Future<void> _pumpSection(
  WidgetTester tester,
  ServiceDetection? detection, {
  DateTime? now,
  void Function(DetectedService)? onOpen,
  VoidCallback? onOpenContainers,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildKelolaDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StackSection(
            detection: detection,
            now: now ?? _readAt.add(const Duration(minutes: 2)),
            onOpen: onOpen ?? (_) {},
            onOpenContainers: onOpenContainers ?? () {},
          ),
        ),
      ),
    ),
  );
}

HostFacts _facts() => const HostFacts(
      osId: 'ubuntu',
      osVersionId: '24.04',
      prettyName: 'Ubuntu 24.04',
      init: InitSystem.systemd,
      systemdVersion: 255,
      pkg: PackageManager.apt,
      fw: FirewallBackend.none,
      hasJournald: true,
      journalReadable: true,
      arch: 'x86_64',
    );

void main() {
  group('StackSection', () {
    test('stackTileMeta', () {
      expect(stackTileMeta(_nginx), '1.24.0 · running');
      expect(stackTileMeta(_apache), 'stopped');
      expect(
        stackTileMeta(
          const DetectedService(id: ServiceId.nginx, state: ServiceState.installed),
        ),
        'installed',
      );
    });

    testWidgets('no detection → no STACK label', (tester) async {
      await _pumpSection(tester, null);
      expect(find.text('STACK'), findsNothing);
      expect(find.byType(ToolTile), findsNothing);

      // Nothing with a lens: hidden too.
      await _pumpSection(tester, _detection(const [_postgres]));
      expect(find.text('STACK'), findsNothing);
      expect(find.byType(ToolTile), findsNothing);

      await _pumpSection(tester, _detection(const []));
      expect(find.text('STACK'), findsNothing);
    });

    testWidgets('two services → two ToolTiles with label and meta',
        (tester) async {
      DetectedService? opened;
      await _pumpSection(
        tester,
        _detection(const [_nginx, _apache]),
        onOpen: (s) => opened = s,
      );
      expect(find.text('STACK'), findsOneWidget);
      final tiles = tester.widgetList<ToolTile>(find.byType(ToolTile)).toList();
      expect(tiles, hasLength(2));
      expect(tiles[0].label, 'nginx');
      expect(tiles[0].meta, '1.24.0 · running');
      expect(tiles[0].status, isNull);
      expect(tiles[1].label, 'Apache httpd');
      expect(tiles[1].meta, 'stopped');
      expect(tiles[1].status, isNull);

      await tester.tap(find.text('Apache httpd'));
      expect(opened?.id, ServiceId.apache);
    });

    testWidgets('stopped containers share one Stopped tile; running, failed '
        'and host services keep theirs', (tester) async {
      var containersOpened = 0;
      DetectedService ctr(String name, ServiceState state) => DetectedService(
        id: ServiceId.apache,
        state: state,
        container: name,
      );
      await _pumpSection(
        tester,
        _detection([
          ctr('lamp-web', ServiceState.running),
          ctr('web-apache', ServiceState.stopped),
          ctr('flappy', ServiceState.failed),
          ctr('old-web', ServiceState.stopped),
          _apache,
        ]),
        onOpenContainers: () => containersOpened++,
      );
      final tiles = tester.widgetList<ToolTile>(find.byType(ToolTile)).toList();
      expect([for (final t in tiles) t.meta], [
        'lamp-web · running',
        'flappy · failed',
        'stopped',
        '2 containers',
      ]);
      expect(tiles.last.label, 'Stopped');
      expect(tiles[1].status, HealthStatus.failed);
      expect(find.text('web-apache · stopped'), findsNothing);

      await tester.tap(find.text('Stopped'));
      expect(containersOpened, 1);
    });

    testWidgets('only stopped containers: STACK shows the Stopped tile',
        (tester) async {
      await _pumpSection(
        tester,
        _detection(const [
          DetectedService(
            id: ServiceId.nginx,
            state: ServiceState.stopped,
            container: 'edge',
          ),
        ]),
      );
      expect(find.text('STACK'), findsOneWidget);
      final tile = tester.widget<ToolTile>(find.byType(ToolTile));
      expect(tile.label, 'Stopped');
      expect(tile.meta, '1 container');
    });

    testWidgets('service without lens (postgres in M52) not shown',
        (tester) async {
      await _pumpSection(tester, _detection(const [_postgres, _nginx]));
      expect(find.text('STACK'), findsOneWidget);
      expect(find.byType(ToolTile), findsOneWidget);
      expect(find.text('PostgreSQL'), findsNothing);
      expect(find.text('nginx'), findsOneWidget);
    });

    testWidgets('failed service tile uses failed status (via the new ToolTile.status)',
        (tester) async {
      await _pumpSection(
        tester,
        _detection(const [
          DetectedService(
            id: ServiceId.nginx,
            state: ServiceState.failed,
            version: '1.24.0',
          ),
          _apache,
        ]),
      );
      final tiles = tester.widgetList<ToolTile>(find.byType(ToolTile)).toList();
      expect(tiles[0].status, HealthStatus.failed);
      expect(tiles[0].meta, '1.24.0 · failed');
      expect(tiles[1].status, isNull);

      final c = KelolaColors.dark;
      final meta = tester.widget<Text>(find.text('1.24.0 · failed'));
      expect(meta.style?.color, c.red);
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byWidget(tiles[0]),
          matching: find.byType(Material),
        ).first,
      );
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.side.color, c.red);
    });

    testWidgets('ToolTile without status renders exactly as before',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildKelolaDarkTheme(),
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: ToolTile(label: 'Logs', meta: 'journalctl', onTap: () {}),
                ),
              ],
            ),
          ),
        ),
      );
      final c = KelolaColors.dark;
      final tile = find.byType(ToolTile);
      final material = tester.widget<Material>(
        find.descendant(of: tile, matching: find.byType(Material)).first,
      );
      final shape = material.shape! as RoundedRectangleBorder;
      expect(material.color, c.surface);
      expect(shape.side.color, c.line);
      expect(shape.borderRadius, BorderRadius.circular(KelolaRadii.sm));
      final label = tester.widget<Text>(find.text('Logs'));
      expect(label.style?.color, c.text);
      final meta = tester.widget<Text>(find.text('journalctl'));
      expect(meta.style?.color, c.muted);
      // Label above meta, nothing else in the column: no status dot.
      final column = tester.widget<Column>(
        find.descendant(of: tile, matching: find.byType(Column)).first,
      );
      expect(column.children, hasLength(3));
      expect(
        find.descendant(of: tile, matching: find.byType(Row)),
        findsNothing,
      );
      expect(tester.getSize(tile).height, 51);
    });

    testWidgets('age label shown and turns warning after 15 min',
        (tester) async {
      final c = KelolaColors.dark;
      await _pumpSection(
        tester,
        _detection(const [_nginx]),
        now: _readAt.add(const Duration(minutes: 10)),
      );
      final fresh = tester.widget<Text>(find.text('read 10m ago'));
      expect(fresh.style?.color, c.dim);
      expect(fresh.style?.fontFamily, KelolaType.mono(color: c.dim).fontFamily);

      await _pumpSection(
        tester,
        _detection(const [_nginx]),
        now: _readAt.add(const Duration(minutes: 22)),
      );
      final stale = tester.widget<Text>(find.text('read 22m ago'));
      expect(stale.style?.color, c.forHealth(HealthStatus.warning));
      // Data stays visible when stale.
      expect(find.text('nginx'), findsOneWidget);
    });
  });

  group('dashboard', () {
    late KelolaDatabase db;
    late HostRepository repo;
    late _Pool pool;
    // Created on first use inside the test body: the store chains writes on
    // a future, which must belong to the test's fake-async zone.
    ServiceLensStore? lensStore;
    ServiceLensStore lenses() => lensStore ??= ServiceLensStore.memory();
    late Host host;

    setUp(() async {
      db = KelolaDatabase.memory();
      repo = HostRepository(db);
      pool = _Pool(repository: repo);
      lensStore = null;
      host = await repo.insert(
        alias: 'web01',
        address: '192.168.1.10',
        port: 22,
        username: 'hendra',
      );
      await repo.saveFacts(host.id, _facts());
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> frames(WidgetTester tester, [int n = 12]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpDashboard(
      WidgetTester tester, {
      Future<ServiceLensStore> Function()? store,
    }) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            hostRepositoryProvider.overrideWithValue(repo),
            sessionPoolProvider.overrideWithValue(pool),
            homeWidgetBridgeProvider
                .overrideWithValue(const _NoopWidgetBridge()),
            hardwareSignerProvider.overrideWithValue(_BoomSigner()),
            enrollmentProvider.overrideWith(_ReadyEnrollment.new),
            clusterKindStoreProvider
                .overrideWith((ref) async => ClusterKindStore.memory()),
            serviceLensStoreProvider.overrideWith(
              (ref) => store != null ? store() : Future.value(lenses()),
            ),
          ],
          child: KelolaApp(home: HostDashboardScreen(hostId: host.id)),
        ),
      );
      await frames(tester);
    }

    Future<void> pullToRefresh(WidgetTester tester) async {
      // Same callback the pull gesture fires.
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await frames(tester, 30);
    }

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('no cache: detection runs after the dashboard read and shows',
        (tester) async {
      pool.detection = _detection(
        const [_nginx],
        at: DateTime.now().toUtc(),
      );
      await pumpDashboard(tester);
      expect(
        pool.probes.map((p) => p.runtimeType),
        [DashboardProbe, ServiceDetectProbe],
      );
      expect(find.text('STACK'), findsOneWidget);
      expect(find.text('nginx'), findsOneWidget);
      expect(find.text('1.24.0 · running'), findsOneWidget);
      // Written to the cache.
      expect((await lenses().read(host.id))!.services.single.id, ServiceId.nginx);
      // STACK sits between the Updates row and TOOLS.
      expect(
        tester.getTopLeft(find.text('STACK')).dy,
        lessThan(tester.getTopLeft(find.text('TOOLS')).dy),
      );
      await dispose(tester);
    });

    testWidgets('no detection → no STACK label', (tester) async {
      pool.detection = _detection(const [], at: DateTime.now().toUtc());
      await pumpDashboard(tester);
      expect(find.text('STACK'), findsNothing);
      expect(find.text('TOOLS'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('removing the host from the dashboard forgets its cached detection',
        (tester) async {
      await lenses().write(
        host.id,
        _detection(const [_nginx], at: DateTime.now().toUtc()),
      );
      await pumpDashboard(tester);
      expect(find.text('nginx'), findsOneWidget);
      await tester.tap(find.byTooltip('More'));
      await frames(tester);
      await tester.tap(find.text('Remove host'));
      await frames(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await frames(tester, 20);
      expect(await repo.get(host.id), isNull);
      expect(await lenses().read(host.id), isNull);
      await dispose(tester);
    });

    testWidgets('fresh cache shows at once and skips detection',
        (tester) async {
      await lenses().write(
        host.id,
        _detection(
          const [_nginx],
          at: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
        ),
      );
      await pumpDashboard(tester);
      expect(pool.probes.map((p) => p.runtimeType), [DashboardProbe]);
      expect(find.text('nginx'), findsOneWidget);
      expect(find.text('read 3m ago'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('stale cache is re-read; a service gone from the new read '
        'disappears', (tester) async {
      await lenses().write(
        host.id,
        _detection(
          const [_nginx, _apache],
          at: DateTime.now().toUtc().subtract(const Duration(minutes: 40)),
        ),
      );
      pool.detection = _detection(
        const [_nginx],
        at: DateTime.now().toUtc(),
      );
      await pumpDashboard(tester);
      expect(
        pool.probes.map((p) => p.runtimeType),
        [DashboardProbe, ServiceDetectProbe],
      );
      expect(find.text('nginx'), findsOneWidget);
      expect(find.text('Apache httpd'), findsNothing);
      expect((await lenses().read(host.id))!.services, hasLength(1));
      await dispose(tester);
    });

    testWidgets('pull-to-refresh always re-detects', (tester) async {
      await lenses().write(
        host.id,
        _detection(const [_nginx], at: DateTime.now().toUtc()),
      );
      pool.detection = _detection(
        const [_nginx, _apache],
        at: DateTime.now().toUtc(),
      );
      await pumpDashboard(tester);
      expect(pool.probes.whereType<ServiceDetectProbe>(), isEmpty);
      await pullToRefresh(tester);
      expect(pool.probes.whereType<ServiceDetectProbe>(), hasLength(1));
      expect(find.text('Apache httpd'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('detection error surfaces only as KelolaError on refresh',
        (tester) async {
      pool.detectError = SshUnavailableException('ss: boom');
      await pumpDashboard(tester);
      expect(pool.probes.whereType<ServiceDetectProbe>(), hasLength(1));
      // Silent on open: no error line, no section, dashboard intact.
      expect(find.textContaining('Could not detect services'), findsNothing);
      expect(find.text('STACK'), findsNothing);
      expect(find.text('TOOLS'), findsOneWidget);
      expect(find.byType(KelolaError), findsNothing);

      await pullToRefresh(tester);
      expect(pool.probes.whereType<ServiceDetectProbe>(), hasLength(2));
      final err = find.byWidgetPredicate(
        (w) =>
            w is KelolaError &&
            w.message.startsWith('Could not detect services: '),
      );
      expect(err, findsOneWidget);
      expect(find.text('TOOLS'), findsOneWidget);
      expect(find.text('STACK'), findsNothing);
      await dispose(tester);
    });

    testWidgets('detection error on refresh keeps the cached section',
        (tester) async {
      await lenses().write(
        host.id,
        _detection(const [_nginx], at: DateTime.now().toUtc()),
      );
      pool.detectError = SshUnavailableException('ss: boom');
      await pumpDashboard(tester);
      await pullToRefresh(tester);
      expect(find.textContaining('Could not detect services: '), findsOneWidget);
      expect(find.text('nginx'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('cache that cannot be read is treated as no cache',
        (tester) async {
      pool.detection = _detection(const [_nginx], at: DateTime.now().toUtc());
      await pumpDashboard(
        tester,
        store: () => Future.value(_BrokenStore()),
      );
      expect(find.byType(KelolaError), findsNothing);
      expect(find.text('nginx'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('tap opens the web lens for that service', (tester) async {
      await lenses().write(
        host.id,
        _detection(const [_nginx], at: DateTime.now().toUtc()),
      );
      await pumpDashboard(tester);
      await tester.tap(find.text('nginx'));
      await frames(tester);
      final screen = tester.widget<WebLensScreen>(find.byType(WebLensScreen));
      expect(screen.hostId, host.id);
      expect(screen.service.id, ServiceId.nginx);
      await dispose(tester);
    });
  });
}

class _BrokenStore extends ServiceLensStore {
  _BrokenStore() : super.memory();

  @override
  Future<ServiceDetection?> read(String hostId) async =>
      throw const FileSystemException('locked', 'service_lens.json');

  @override
  Future<void> write(String hostId, ServiceDetection detection) async =>
      throw const FileSystemException('locked', 'service_lens.json');
}

class _Pool extends SshSessionPool {
  _Pool({required super.repository})
      : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(0),
        );

  final probes = <Probe<dynamic>>[];
  ServiceDetection? detection;
  Object? detectError;

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
    probes.add(probe);
    if (probe is DashboardProbe) {
      return const DashboardSnapshot(
        uptime: Duration(hours: 1),
        load1: 0.1,
        cpuPercent: 1,
        memUsedPercent: 20,
        diskRootPercent: 40,
        failedUnitCount: 0,
        failedUnitNames: [],
      ) as T;
    }
    if (probe is ServiceDetectProbe) {
      final err = detectError;
      if (err != null) {
        throw err;
      }
      return (detection ?? _detection(const [], at: DateTime.now().toUtc()))
          as T;
    }
    throw StateError('unexpected probe ${probe.runtimeType}');
  }
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _NoopWidgetBridge implements HomeWidgetBridge {
  const _NoopWidgetBridge();

  @override
  Future<void> write(HomeWidgetSnapshot snap) async {}
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('no key');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('no key');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {}

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
