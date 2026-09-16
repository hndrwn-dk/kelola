import 'dart:io';
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
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_entry.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/sftp_probe.dart';
import 'package:kelola/presentation/screens/files_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late Host host;
  late Directory docs;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    host = await repo.insert(
      alias: 'nas-01',
      address: '10.0.0.2',
      port: 22,
      username: 'hendra',
    );
    docs = await Directory.systemTemp.createTemp('kelola-files-');
  });

  tearDown(() async {
    await db.close();
    if (docs.existsSync()) {
      docs.deleteSync(recursive: true);
    }
  });

  Future<void> pumpFiles(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(
            _FilesPool(repository: repo),
          ),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: KelolaApp(
          home: FilesScreen(
            hostId: host.id,
            transferDocumentsDir: docs,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> pressUpload(WidgetTester tester) async {
    final upload = tester.widgetList<IconButton>(find.byType(IconButton)).last;
    await tester.runAsync(() async {
      upload.onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  testWidgets('opening Files with an empty transfer dir shows no upload tip',
      (tester) async {
    await pumpFiles(tester);

    expect(find.text(filesEmptyUploadHint), findsNothing);
    expect(find.byType(KelolaError), findsNothing);
  });

  testWidgets(
    'upload with empty transfer dir shows a neutral tip, not KelolaError',
    (tester) async {
      await pumpFiles(tester);
      await pressUpload(tester);

      expect(find.text(filesEmptyUploadHint), findsOneWidget);
      expect(find.byType(KelolaError), findsNothing);
      final tip = tester.widget<Text>(find.text(filesEmptyUploadHint));
      expect(tip.style!.color, isNot(KelolaColors.dark.red));
    },
  );
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
    throw StateError('files screen test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('files screen test must not open SSH');
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

class _FilesPool extends SshSessionPool {
  _FilesPool({required super.repository})
      : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(0),
        );

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
    if (probe is SftpListProbe) {
      return SftpListing(
        path: '/',
        entries: const [
          SftpEntry(
            name: 'home',
            path: '/home',
            isDirectory: true,
            owner: 'root',
            group: 'root',
            permissions: 'drwxr-xr-x',
          ),
        ],
      ) as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}
