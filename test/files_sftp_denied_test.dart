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
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_entry.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/sftp_probe.dart';
import 'package:kelola/presentation/screens/files_screen.dart';
import 'package:kelola/presentation/widgets/confirm_file_action.dart';
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
      username: 'hendr',
    );
    docs = await Directory.systemTemp.createTemp('kelola-sftp-denied-');
  });

  tearDown(() async {
    await db.close();
    if (docs.existsSync()) {
      docs.deleteSync(recursive: true);
    }
  });

  Future<void> pumpFiles(
    WidgetTester tester, {
    Future<File?> Function()? pickPhoneFile,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(
            _DeniedPool(repository: repo),
          ),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: KelolaApp(
          home: FilesScreen(
            hostId: host.id,
            transferDocumentsDir: docs,
            pickPhoneFile: pickPhoneFile,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> pressTooltip(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('denied sheet names the login and keeps the path', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
        ],
        child: KelolaApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showSftpDeniedSheet(
                    context,
                    message: 'Permission denied',
                    path: '/home/denied',
                    username: 'hendr',
                  );
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(KelolaSheet), findsNothing);
    expect(find.byType(ActionableError), findsOneWidget);
    expect(find.text('Permission denied'), findsOneWidget);
    expect(find.textContaining('hendr'), findsOneWidget);
    expect(find.text('/home/denied'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('mkdir permission denied stays visible after listing reload',
      (tester) async {
    await pumpFiles(tester);
    await tester.pumpAndSettle();
    expect(find.text('hendr'), findsOneWidget);

    await pressTooltip(tester, 'New directory');
    await tester.enterText(find.byType(TextField), 'other');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('outside that home directory'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Permission denied'), findsWidgets);
    expect(find.byType(ActionableError), findsOneWidget);
    expect(find.textContaining('hendr'), findsWidgets);
    expect(find.text('/home/other'), findsOneWidget);
  });

  testWidgets(
    'pick from this phone permission denied shows the same sheet',
    (tester) async {
      final local = File('${docs.path}/note.txt')..writeAsStringSync('hi');
      await pumpFiles(tester, pickPhoneFile: () async => local);
      await tester.pumpAndSettle();

      await pressTooltip(tester, 'Upload');
      await tester.tap(find.text(filesPickFromPhoneLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Upload from this phone?'), findsOneWidget);
      expect(find.textContaining('outside that home directory'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ActionableError), findsOneWidget);
      expect(find.text('Permission denied'), findsWidgets);
      expect(find.textContaining('hendr'), findsWidgets);
      expect(find.text('/home/note.txt'), findsOneWidget);
    },
  );

  testWidgets('Home returns to the login home directory', (tester) async {
    await pumpFiles(tester);
    await tester.pumpAndSettle();
    expect(find.text('hendr'), findsOneWidget);

    await pressTooltip(tester, 'Home');
    await tester.pumpAndSettle();
    expect(find.text('notes'), findsOneWidget);
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
    throw StateError('files denied test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('files denied test must not open SSH');
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

class _DeniedPool extends SshSessionPool {
  _DeniedPool({required super.repository})
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
      final list = probe as SftpListProbe;
      if (list.path == '/home/hendr') {
        return SftpListing(
          path: '/home/hendr',
          entries: const [
            SftpEntry(
              name: 'notes',
              path: '/home/hendr/notes',
              isDirectory: true,
              owner: 'hendr',
              group: 'hendr',
              permissions: 'drwxr-xr-x',
            ),
          ],
        ) as T;
      }
      return SftpListing(
        path: '/home',
        entries: const [
          SftpEntry(
            name: 'hendr',
            path: '/home/hendr',
            isDirectory: true,
            owner: 'hendr',
            group: 'hendr',
            permissions: 'drwxr-xr-x',
          ),
        ],
      ) as T;
    }
    if (probe is SftpMkdirProbe || probe is SftpUploadProbe) {
      throw KelolaException('Permission denied');
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}
