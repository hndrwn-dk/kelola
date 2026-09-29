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
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/package_list_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/presentation/screens/packages_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late Host host;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    host = await repo.insert(
      alias: 'nas-01',
      address: '10.0.0.2',
      port: 22,
      username: 'hendr',
    );
    await repo.saveFacts(
      host.id,
      const HostFacts(
        osId: 'ubuntu',
        osVersionId: '24.04',
        init: InitSystem.systemd,
        systemdVersion: 255,
        pkg: PackageManager.apt,
        fw: FirewallBackend.none,
        hasJournald: true,
        journalReadable: true,
        arch: 'x86_64',
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('fetching copy shows until the repository list returns',
      (tester) async {
    final gate = Completer<PackageSnapshot>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(
            _PackagesPool(repository: repo, list: () => gate.future),
          ),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: KelolaApp(home: PackagesScreen(hostId: host.id)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('FETCHING UPDATES'), findsOneWidget);
    expect(find.text(packagesFetchingCopy), findsOneWidget);
    expect(find.text('ALL 0'), findsNothing);

    gate.complete(
      const PackageSnapshot(
        manager: PackageManager.apt,
        updates: [
          PackageUpdate(name: 'openssl', security: true),
          PackageUpdate(name: 'curl'),
        ],
        rebootRequired: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('FETCHING UPDATES'), findsNothing);
    expect(find.text('openssl'), findsOneWidget);
    expect(find.text('Apply 1 security updates'), findsOneWidget);

    final cached = (await repo.loadFleetCacheByHost())[host.id]!;
    expect(cached.pendingUpdates, 2);
    expect(cached.securityUpdates, 1);
  });

  testWidgets('apply opens DestructiveConfirmSheet before upgrading',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(
            _PackagesPool(
              repository: repo,
              list: () async => const PackageSnapshot(
                manager: PackageManager.apt,
                updates: [
                  PackageUpdate(name: 'openssl', security: true),
                  PackageUpdate(name: 'curl'),
                ],
                rebootRequired: false,
              ),
            ),
          ),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: KelolaApp(home: PackagesScreen(hostId: host.id)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply 1 security updates'));
    await tester.pumpAndSettle();
    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Apply 1 security updates?'), findsOneWidget);
  });

  testWidgets('sudo-gated dnf refresh shows ActionableError, not ALL 0',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(
            _PackagesPool(
              repository: repo,
              list: () async => throw SudoRequiredException(
                const SudoHintContext(
                  kind: SudoHintKind.packages,
                  binary: '/usr/bin/dnf check-update --refresh',
                  verb: 'check-update',
                ),
              ),
            ),
          ),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: KelolaApp(home: PackagesScreen(hostId: host.id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ActionableError), findsOneWidget);
    expect(find.textContaining('dnf check-update --refresh'), findsWidgets);
    expect(find.textContaining('hendr ALL=(root) NOPASSWD'), findsWidgets);
    expect(find.textContaining('FETCHING UPDATES'), findsNothing);
    expect(find.text(packagesFetchingCopy), findsNothing);
    expect(find.text('ALL 0'), findsNothing);
  });

  testWidgets('leaving Packages cancels the in-flight list', (tester) async {
    final gate = Completer<PackageSnapshot>();
    final pool = _PackagesPool(
      repository: repo,
      list: () => gate.future,
    );
    final overrides = [
      databaseProvider.overrideWithValue(db),
      hostRepositoryProvider.overrideWithValue(repo),
      sessionPoolProvider.overrideWithValue(pool),
      enrollmentProvider.overrideWith(_ReadyEnrollment.new),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: KelolaApp(home: PackagesScreen(hostId: host.id)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(pool.cancel, isNotNull);
    expect(pool.cancel!.isCancelled, isFalse);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const SizedBox.shrink(),
      ),
    );
    expect(pool.cancel!.isCancelled, isTrue);
    gate.complete(
      const PackageSnapshot(
        manager: PackageManager.apt,
        updates: [],
        rebootRequired: false,
      ),
    );
  });
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('packages test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('packages test must not open SSH');
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

class _PackagesPool extends SshSessionPool {
  _PackagesPool({
    required super.repository,
    required this.list,
  }) : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(0),
        );

  final Future<PackageSnapshot> Function() list;

  TransferCancel? cancel;

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
    this.cancel = cancel;
    if (probe is HostFactsProbe) {
      throw StateError('facts must be cached');
    }
    if (probe is PackageListProbe) {
      return await list() as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}
