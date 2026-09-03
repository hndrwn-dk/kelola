import 'dart:async';
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
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/journal/journal_follow.dart';
import 'package:kelola/domain/probes/journal_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/presentation/screens/journal_screen.dart';
import 'package:kelola/providers.dart';

const _facts = HostFacts(
  osId: 'debian',
  osVersionId: '12',
  init: InitSystem.systemd,
  systemdVersion: 252,
  pkg: PackageManager.apt,
  fw: FirewallBackend.ufw,
  hasJournald: true,
  journalReadable: true,
  arch: 'x86_64',
);

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late _JournalPool pool;
  late _FakeFollowChannel channel;
  late Host host;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    host = await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );
    await repo.saveFacts(host.id, _facts);
    channel = _FakeFollowChannel();
    pool = _JournalPool(
      repository: repo,
      followOpener: ({
        required Host host,
        required String command,
        UnknownHostKeyHandler? onUnknownHostKey,
      }) async =>
          channel,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpLogs(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(pool),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: KelolaApp(home: JournalScreen(hostId: host.id)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('live chip is enabled and uses JournalLogLine', (tester) async {
    await pumpLogs(tester);
    expect(find.byType(JournalLogLine), findsOneWidget);
    final live = tester.widget<FilterPill>(
      find.widgetWithText(FilterPill, 'LIVE'),
    );
    expect(live.enabled, isTrue);
    expect(live.selected, isFalse);
  });

  testWidgets('leaving the logs screen closes the follow SSH channel',
      (tester) async {
    await pumpLogs(tester);
    await tester.tap(find.widgetWithText(FilterPill, 'LIVE'));
    await tester.pump();
    await tester.pump();
    expect(pool.activeFollowCount, 1);
    expect(channel.closed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(channel.closed, isTrue);
    expect(pool.activeFollowCount, 0);
  });

  testWidgets('live follow shows a line that arrives after the session is open',
      (tester) async {
    await pumpLogs(tester);
    expect(find.textContaining('kelolatest ping'), findsNothing);

    await tester.tap(find.widgetWithText(FilterPill, 'LIVE'));
    await tester.pump();
    await tester.pump();
    expect(pool.activeFollowCount, 1);
    expect(find.textContaining('kelolatest ping'), findsNothing);

    channel.addText(
      '{"__CURSOR":"live-1","__REALTIME_TIMESTAMP":"1756877023000000",'
      '"PRIORITY":"6","MESSAGE":"kelolatest ping"}\n',
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(JournalLogLine), findsNWidgets(2));
    expect(find.textContaining('kelolatest ping'), findsOneWidget);
    expect(channel.closed, isFalse);
    expect(pool.activeFollowCount, 1);
  });

  testWidgets('live chip turns off when the follow stream ends', (tester) async {
    await pumpLogs(tester);
    await tester.tap(find.widgetWithText(FilterPill, 'LIVE'));
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<FilterPill>(find.widgetWithText(FilterPill, 'LIVE')).selected,
      isTrue,
    );

    await channel.close();
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<FilterPill>(find.widgetWithText(FilterPill, 'LIVE')).selected,
      isFalse,
    );
  });
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _JournalPool extends SshSessionPool {
  _JournalPool({
    required super.repository,
    required JournalFollowOpener followOpener,
  }) : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
          followOpener: followOpener,
        );

  @override
  Future<T> execute<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    if (probe is JournalProbe) {
      return JournalPage(
        entries: const [
          JournalEntry(
            cursor: 'c1',
            realtimeUsec: '1756721400000000',
            priority: 3,
            message: 'Failed to bind',
          ),
        ],
        permissionDenied: false,
      ) as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

class _FakeFollowChannel implements JournalFollowChannel {
  final _stdout = StreamController<List<int>>();
  var closed = false;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  bool get isClosed => closed;

  void addText(String text) {
    _stdout.add(utf8.encode(text));
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_stdout.isClosed) {
      await _stdout.close();
    }
  }
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('journal screen test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('journal screen test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
