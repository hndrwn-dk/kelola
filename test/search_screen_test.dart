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
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
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
  Future<void> confirmPresence({String reason = 'Confirm destructive action'}) async {
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
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
    ProbeScope scope = ProbeScope.host,
  }) {
    // Match real SFTP path: cancelled transfers abort before any work.
    if (cancel?.isCancelled == true) {
      throw const TransferCancelledException();
    }
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

  Future<void> pumpSearch(WidgetTester tester) async {
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
  }

  testWidgets('idle and typed-miss empty states are distinct', (tester) async {
    await pumpSearch(tester);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('LOCAL'), findsOneWidget);
    expect(
      find.text('Search hosts by name, address, or tag.'),
      findsOneWidget,
    );
    expect(find.text('east-worker-uat'), findsNothing);
    expect(find.text('No matches.'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.text('No hosts match.'), findsOneWidget);
    expect(
      find.text('Search hosts by name, address, or tag.'),
      findsNothing,
    );
    expect(find.byType(FilterPill), findsNothing);
    expect(find.text('0 MATCHES'), findsOneWidget);
    expect(pool.executeCalls, 0);
  });

  testWidgets('a host match is a ServiceRow; unit names stay off this screen',
      (tester) async {
    final stored = (await repo.list()).single;
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: stored.id,
      parsed: const UnitListResult(
        units: [
          ServiceUnit(
            name: 'nginx.service',
            description: '',
            load: 'loaded',
            active: 'failed',
            sub: 'failed',
          ),
        ],
        initSupported: true,
      ),
    );
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: stored.id,
      parsed: const ContainerInventory(
        rows: [
          ContainerRow(
            id: 'c1',
            names: 'nginx',
            image: 'nginx:latest',
            state: 'running',
            status: 'Up 2 days',
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
    expect(find.byType(ServiceRow), findsNothing);
    expect(find.text('nginx.service'), findsNothing);
    expect(find.text('No hosts match.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'east');
    await tester.pump();
    expect(find.byType(ServiceRow), findsOneWidget);
    expect(find.byType(HostCard), findsNothing);
    expect(find.text('east-worker-uat'), findsOneWidget);
    expect(find.text('host · 192.168.18.114'), findsOneWidget);
    expect(find.text('1 MATCHES'), findsOneWidget);
    expect(find.byType(FilterPill), findsNothing);
    expect(pool.executeCalls, 0);

    await tester.enterText(find.byType(TextField), 'hendra');
    await tester.pump();
    expect(find.byType(ServiceRow), findsNothing);
    expect(find.text('No hosts match.'), findsOneWidget);
    expect(pool.executeCalls, 0);
  });
}
