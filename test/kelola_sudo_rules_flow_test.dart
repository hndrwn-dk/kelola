import 'dart:convert';
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
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/sudo/kelola_sudo_files.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';
import 'package:kelola/presentation/widgets/kelola_sudo_rules_flow.dart';
import 'package:kelola/providers.dart';

// The presentation side of removing a Kelola sudo line: presence, the sudo
// password over stdin only, then the destructive probe.

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late _Pool pool;
  late _Signer signer;
  late Host host;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    signer = _Signer();
    pool = _Pool(repository: repo, signer: signer);
    host = await repo.insert(
      alias: 'web01',
      address: '192.168.1.10',
      port: 22,
      username: 'hendra',
    );
  });

  tearDown(() async => db.close());

  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(pool),
          hardwareSignerProvider.overrideWithValue(signer),
        ],
        child: KelolaApp(
          home: Scaffold(
            body: Consumer(
              builder: (c, ref, _) {
                ctx = c;
                _ref = ref;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    return ctx;
  }

  Future<void> enterPassword(WidgetTester tester, {String value = 's3cret'}) async {
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), value);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
  }

  testWidgets('remove: presence first, then the password, then the probe', (
    tester,
  ) async {
    final ctx = await pump(tester);
    const removal = (
      path: kelolaWebSudoersPath,
      line: 'hendra ALL=(root) NOPASSWD: /usr/sbin/nginx -t',
    );
    final done = removeKelolaSudoRule(
      context: ctx,
      ref: _ref,
      host: host,
      removal: removal,
    );
    await tester.pumpAndSettle();
    // Presence was asked before the password sheet opened.
    expect(signer.presence, ['Removed a line from $kelolaWebSudoersPath']);
    expect(pool.probes, isEmpty);
    await enterPassword(tester);
    await done;
    final p = pool.probes.single as KelolaSudoRemoveProbe;
    expect(p.path, kelolaWebSudoersPath);
    expect(p.line, removal.line);
    expect(pool.stdin, utf8.encode('s3cret\n'));
    expect(p.command(HostFacts.undiscovered), isNot(contains('s3cret')));
  });

  testWidgets('remove: a cancelled password changes nothing', (tester) async {
    final ctx = await pump(tester);
    final done = expectLater(
      removeKelolaSudoRule(
        context: ctx,
        ref: _ref,
        host: host,
        removal: (path: kelolaSudoersPath, line: null),
      ),
      throwsA(isA<KelolaException>()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    await done;
    expect(pool.probes, isEmpty);
  });

  testWidgets('remove: a refused presence prompt runs nothing', (tester) async {
    signer.refuse = true;
    final ctx = await pump(tester);
    await expectLater(
      removeKelolaSudoRule(
        context: ctx,
        ref: _ref,
        host: host,
        removal: (path: kelolaSudoersPath, line: null),
      ),
      throwsA(isA<HardwareSignerException>()),
    );
    expect(pool.probes, isEmpty);
  });

  testWidgets('remove: a path outside the Kelola files is refused', (tester) async {
    final ctx = await pump(tester);
    await expectLater(
      removeKelolaSudoRule(
        context: ctx,
        ref: _ref,
        host: host,
        removal: (path: '/etc/sudoers.d/90-cloud-init-users', line: null),
      ),
      throwsArgumentError,
    );
    expect(signer.presence, isEmpty);
    expect(pool.probes, isEmpty);
  });

  testWidgets('read with password: the password goes over stdin', (tester) async {
    final ctx = await pump(tester);
    final done = readKelolaSudoFilesWithPassword(
      context: ctx,
      ref: _ref,
      host: host,
    );
    await enterPassword(tester);
    final files = await done;
    expect(files.files, isEmpty);
    final p = pool.probes.single as KelolaSudoFilesProbe;
    expect(p.withPassword, isTrue);
    expect(pool.stdin, utf8.encode('s3cret\n'));
    // No presence for a read.
    expect(signer.presence, isEmpty);
  });

  testWidgets('read with password: cancelled reads without it', (tester) async {
    final ctx = await pump(tester);
    final done = readKelolaSudoFilesWithPassword(
      context: ctx,
      ref: _ref,
      host: host,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    await done;
    final p = pool.probes.single as KelolaSudoFilesProbe;
    expect(p.withPassword, isFalse);
    expect(pool.stdin, isNull);
  });
}

late WidgetRef _ref;

class _Pool extends SshSessionPool {
  _Pool({required super.repository, required super.signer})
    : super(
        hostKeys: HostKeyPolicy(repository),
        publicBlob: () => Uint8List(0),
      );

  final probes = <Probe<dynamic>>[];
  List<int>? stdin;

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
    stdin = stdinBytes;
    if (probe is KelolaSudoRemoveProbe) {
      return probe.parse('$kelolaSudoRemoveOkMarker\n@deleted=0\n', '', 0);
    }
    if (probe is KelolaSudoFilesProbe) {
      return probe.parse('---LIST---\n', '', 0);
    }
    throw StateError('unexpected probe ${probe.runtimeType}');
  }
}

class _Signer implements HardwareSigner {
  final presence = <String>[];
  bool refuse = false;

  @override
  Future<HardwareKey> generateKey(String alias) async => throw StateError('no');

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async =>
      throw StateError('no');

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    if (refuse) throw HardwareSignerException('cancelled');
    presence.add(reason);
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
