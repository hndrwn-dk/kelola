import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/search/inventory_search.dart';
import 'package:kelola/domain/search/search_index_write.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/presentation/screens/search_screen.dart';
import 'package:kelola/presentation/widgets/host_card.dart';
import 'package:kelola/providers.dart';

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('search must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('search must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async {
    throw StateError('search must not open SSH');
  }

  @override
  Future<void> deleteKey(String alias) async {
    throw StateError('search must not open SSH');
  }
}

class _NoSshPool extends SshSessionPool {
  _NoSshPool({required super.repository})
      : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => throw StateError('search must not open SSH'),
        );

  int executeCalls = 0;

  @override
  Future<T> execute<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
  }) {
    executeCalls++;
    throw StateError('search must not open SSH');
  }
}

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late _NoSshPool pool;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    pool = _NoSshPool(repository: repo);
    await repo.insert(
      alias: 'east-worker-uat',
      address: '192.168.18.114',
      port: 22,
      username: 'hendra',
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpSearch(
    WidgetTester tester, {
    List<SearchUnit> units = const [],
    List<SearchContainer> containers = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionPoolProvider.overrideWithValue(pool),
          cachedSearchUnitsProvider.overrideWithValue(units),
          cachedSearchContainersProvider.overrideWithValue(containers),
        ],
        child: const KelolaApp(home: SearchScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('idle and typed-miss empty states are distinct', (tester) async {
    await pumpSearch(tester);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('LOCAL'), findsOneWidget);
    expect(
      find.text('Search hosts, units, and containers already on this phone.'),
      findsOneWidget,
    );
    expect(find.text('east-worker-uat'), findsNothing);
    expect(find.text('No matches.'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.text('No matches.'), findsOneWidget);
    expect(
      find.text('Search hosts, units, and containers already on this phone.'),
      findsNothing,
    );
    expect(find.text('0 MATCHES'), findsOneWidget);
    expect(pool.executeCalls, 0);
  });

  testWidgets('results are ServiceRows with type · origin meta; no HostCard',
      (tester) async {
    await pumpSearch(
      tester,
      units: [
        SearchUnit(
          hostId: 'east-worker-uat',
          hostAlias: 'east-worker-uat',
          unit: const ServiceUnit(
            name: 'nginx.service',
            description: '',
            load: 'loaded',
            active: 'failed',
            sub: 'failed',
          ),
        ),
      ],
      containers: [
        SearchContainer(
          hostId: 'east-worker-uat',
          hostAlias: 'east-worker-uat',
          row: const ContainerRow(
            id: 'c1',
            names: 'nginx',
            image: 'nginx:latest',
            state: 'running',
            status: 'Up 2 days',
          ),
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'nginx');
    await tester.pump();

    expect(find.byType(ServiceRow), findsNWidgets(2));
    expect(find.byType(HostCard), findsNothing);
    expect(find.text('nginx.service'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ServiceRow), matching: find.text('nginx')),
      findsOneWidget,
    );
    expect(find.text('unit · east-worker-uat'), findsOneWidget);
    expect(find.text('container · east-worker-uat'), findsOneWidget);
    expect(find.text('2 MATCHES'), findsOneWidget);
    expect(pool.executeCalls, 0);
  });

  testWidgets('type chips filter; empty filter shows empty state with counts',
      (tester) async {
    await pumpSearch(
      tester,
      units: [
        SearchUnit(
          hostId: 'east-worker-uat',
          hostAlias: 'east-worker-uat',
          unit: const ServiceUnit(
            name: 'nginx.service',
            description: '',
            load: 'loaded',
            active: 'active',
            sub: 'running',
          ),
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'east');
    await tester.pump();

    expect(find.text('east-worker-uat'), findsWidgets);
    expect(find.text('host · 192.168.18.114'), findsOneWidget);
    expect(find.text('HOSTS 1'), findsOneWidget);
    expect(find.text('UNITS 0'), findsOneWidget);
    expect(find.text('CONTAINERS 0'), findsOneWidget);
    expect(find.text('ALL 1'), findsOneWidget);

    await tester.tap(find.text('UNITS 0'));
    await tester.pump();

    expect(find.text('No units match.'), findsOneWidget);
    expect(find.byType(ServiceRow), findsNothing);
    expect(find.text('1 MATCHES'), findsOneWidget);

    await tester.tap(find.text('HOSTS 1'));
    await tester.pump();

    expect(find.byType(ServiceRow), findsOneWidget);
    expect(find.text('host · 192.168.18.114'), findsOneWidget);
    expect(pool.executeCalls, 0);
  });

  testWidgets(
      'UnitsProbe index is read locally: nginx names host without execute',
      (tester) async {
    final stored = await repo.list();
    final host = stored.single;
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: const UnitListResult(
        units: [
          ServiceUnit(
            name: 'nginx.service',
            description: '',
            load: 'loaded',
            active: 'active',
            sub: 'running',
          ),
        ],
        initSupported: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionPoolProvider.overrideWithValue(pool),
        ],
        child: const KelolaApp(home: SearchScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'nginx');
    await tester.pump();
    await tester.pump();

    expect(find.text('nginx.service'), findsOneWidget);
    expect(find.text('unit · east-worker-uat'), findsOneWidget);
    expect(find.text('UNITS 1'), findsOneWidget);
    expect(pool.executeCalls, 0);
  });

  testWidgets(
      'ContainerListProbe index is read locally without execute',
      (tester) async {
    final host = (await repo.list()).single;
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: const ContainerInventory(
        rows: [
          ContainerRow(
            id: 'c1',
            names: 'nginx',
            image: 'nginx:latest',
            state: 'running',
            status: 'Up 1 day',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionPoolProvider.overrideWithValue(pool),
        ],
        child: const KelolaApp(home: SearchScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'nginx');
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(of: find.byType(ServiceRow), matching: find.text('nginx')),
      findsOneWidget,
    );
    expect(find.text('container · east-worker-uat'), findsOneWidget);
    expect(find.text('CONTAINERS 1'), findsOneWidget);
    expect(pool.executeCalls, 0);
  });

  testWidgets('stale unit hit still appears with age in meta', (tester) async {
    final host = (await repo.list()).single;
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: const UnitListResult(
        units: [
          ServiceUnit(
            name: 'nginx.service',
            description: '',
            load: 'loaded',
            active: 'active',
            sub: 'running',
          ),
        ],
        initSupported: true,
      ),
      now: DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionPoolProvider.overrideWithValue(pool),
        ],
        child: const KelolaApp(home: SearchScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'nginx');
    await tester.pump();
    await tester.pump();

    expect(find.text('nginx.service'), findsOneWidget);
    expect(find.text('unit · east-worker-uat · 20m ago'), findsOneWidget);
    expect(pool.executeCalls, 0);
  });
}
