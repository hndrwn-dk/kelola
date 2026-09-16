import 'dart:async';
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
import 'package:kelola/domain/containers/container_detail.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/container_inspect_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/unit_detail_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/presentation/screens/container_detail_screen.dart';
import 'package:kelola/presentation/screens/unit_detail_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

const _host = Host(
  id: 'h1',
  alias: 'nas-01',
  address: '10.0.0.2',
  port: 22,
  username: 'hendra',
  keyAlias: 'kelola',
);

const _row = ContainerRow(
  id: 'abc',
  names: 'web',
  image: 'nginx',
  state: 'running',
  status: 'Up',
);

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('detail test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('detail test must not open SSH');
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

class _ScriptedPool extends SshSessionPool {
  _ScriptedPool({required super.repository, required this.onExecute})
      : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(0),
        );

  final Future<Object?> Function(Probe<dynamic> probe) onExecute;

  @override
  Future<T> execute<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
    ProbeScope scope = ProbeScope.host,
  }) async {
    final value = await onExecute(probe);
    return value as T;
  }
}

void main() {
  late KelolaDatabase db;

  setUp(() {
    db = KelolaDatabase.memory();
  });

  tearDown(() => db.close());

  Future<void> pumpContainer(
    WidgetTester tester,
    Future<Object?> Function(Probe<dynamic> probe) onExecute,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionPoolProvider.overrideWithValue(
            _ScriptedPool(repository: HostRepository(db), onExecute: onExecute),
          ),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: const KelolaApp(
          home: ContainerDetailScreen(
            host: _host,
            facts: HostFacts.undiscovered,
            row: _row,
          ),
        ),
      ),
    );
  }

  Future<void> pumpUnit(
    WidgetTester tester,
    Future<Object?> Function(Probe<dynamic> probe) onExecute,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionPoolProvider.overrideWithValue(
            _ScriptedPool(repository: HostRepository(db), onExecute: onExecute),
          ),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: const KelolaApp(
          home: UnitDetailScreen(
            host: _host,
            facts: HostFacts.undiscovered,
            unitName: 'nginx.service',
          ),
        ),
      ),
    );
  }

  testWidgets('container detail stays loading until inspect returns', (
    tester,
  ) async {
    final gate = Completer<ContainerDetail>();
    await pumpContainer(tester, (probe) {
      expect(probe, isA<ContainerInspectProbe>());
      return gate.future;
    });
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(KelolaEmpty), findsNothing);
    expect(find.byType(KelolaError), findsNothing);
    expect(find.text('Restart'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(const ContainerDetail(name: 'web'));
    await tester.pump();
  });

  testWidgets('silent empty container inspect hides actions', (tester) async {
    await pumpContainer(tester, (_) async => const ContainerDetail(name: ''));
    await tester.pump();
    await tester.pump();

    expect(find.byType(KelolaEmpty), findsOneWidget);
    expect(find.text('No inspect data'), findsOneWidget);
    expect(find.byType(KelolaError), findsNothing);
    expect(find.text('Restart'), findsNothing);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('container inspect failure is an error, not actions', (
    tester,
  ) async {
    await pumpContainer(tester, (_) async => throw StateError('inspect blew'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(KelolaError), findsOneWidget);
    expect(find.byType(KelolaEmpty), findsNothing);
    expect(find.text('Restart'), findsNothing);
    expect(find.textContaining('inspect blew'), findsOneWidget);
  });

  testWidgets('unit detail stays loading until show returns', (tester) async {
    final gate = Completer<UnitDetail>();
    await pumpUnit(tester, (probe) {
      expect(probe, isA<UnitDetailProbe>());
      return gate.future;
    });
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(KelolaEmpty), findsNothing);
    expect(find.byType(KelolaError), findsNothing);
    expect(find.text('Restart'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(
      const UnitDetail(
        name: 'nginx.service',
        properties: {'ActiveState': 'active'},
        logs: '',
        dependencies: '',
      ),
    );
    await tester.pump();
  });

  testWidgets('silent empty unit inspect hides actions', (tester) async {
    await pumpUnit(
      tester,
      (_) async => const UnitDetail(
        name: 'nginx.service',
        properties: {},
        logs: '',
        dependencies: '',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(KelolaEmpty), findsOneWidget);
    expect(find.text('No unit data'), findsOneWidget);
    expect(find.byType(KelolaError), findsNothing);
    expect(find.text('Restart'), findsNothing);
  });

  testWidgets('unit inspect failure is an error, not actions', (tester) async {
    await pumpUnit(tester, (_) async => throw StateError('show blew'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(KelolaError), findsOneWidget);
    expect(find.byType(KelolaEmpty), findsNothing);
    expect(find.text('Restart'), findsNothing);
    expect(find.textContaining('show blew'), findsOneWidget);
  });
}
