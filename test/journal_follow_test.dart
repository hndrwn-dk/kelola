import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/journal/journal_follow.dart';
import 'package:kelola/domain/probes/journal_probe.dart';

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

const _host = Host(
  id: 'h1',
  alias: 'nas-01',
  address: '192.168.1.24',
  port: 22,
  username: 'hendra',
  keyAlias: 'kelola-user',
);

void main() {
  test('follow command is journalctl -o json -f, not a snapshot probe', () {
    const follow = JournalFollowCommand(unit: 'nginx.service', priority: 3);
    final cmd = follow.command(_facts);
    expect(cmd, contains('journalctl -o json --no-pager -f'));
    expect(cmd, contains('-u \'nginx.service\''));
    expect(cmd, contains('-p 3'));
    expect(cmd, isNot(contains('--reverse')));
    expect(cmd, isNot(contains(r'out=$(journalctl')));
    expect(
      const JournalProbe().command(_facts),
      isNot(contains('journalctl -o json --no-pager -f')),
    );
    expect(journalFollowRequiresPty, isTrue);
  });

  test('host-wide follow tails syslog so logger -t lines arrive', () {
    final cmd = const JournalFollowCommand().command(_facts);
    expect(cmd, contains('tail -n 0 -F /var/log/syslog'));
    expect(cmd, isNot(contains(r'out=$(journalctl')));
    expect(cmd, isNot(contains('---NOJOURNAL---')));
  });

  test('follow command degrades when journald is absent', () {
    expect(
      const JournalFollowCommand().command(HostFacts.undiscovered),
      contains('---NOJOURNAL---'),
    );
  });

  test('cancel closes the SSH channel and drops the follow', () async {
    final channel = _FakeFollowChannel();
    final handle = JournalFollowHandle.bind(
      channel: channel,
      onEntry: (_) {},
    );
    expect(handle.isOpen, isTrue);
    expect(channel.closed, isFalse);
    await handle.cancel();
    expect(handle.isOpen, isFalse);
    expect(channel.closed, isTrue);
  });

  test('follow parses chunks incrementally then cancel still closes', () async {
    final channel = _FakeFollowChannel();
    final got = <JournalEntry>[];
    final handle = JournalFollowHandle.bind(
      channel: channel,
      onEntry: got.add,
    );
    channel.addText(
      '{"__CURSOR":"a","__REALTIME_TIMESTAMP":"1","PRIORITY":"6","MESSAGE":"Hel',
    );
    await pumpEventQueue();
    expect(got, isEmpty);
    channel.addText('lo"}\n');
    await pumpEventQueue();
    expect(got, hasLength(1));
    expect(got.single.message, 'Hello');
    await handle.cancel();
    expect(channel.closed, isTrue);
  });

  test('follow delivers a line that arrives after the session is already open',
      () async {
    final channel = _FakeFollowChannel();
    final got = <JournalEntry>[];
    final handle = JournalFollowHandle.bind(
      channel: channel,
      onEntry: got.add,
    );
    expect(got, isEmpty);
    channel.addText(
      '{"__CURSOR":"live-1","__REALTIME_TIMESTAMP":"1756877023000000",'
      '"PRIORITY":"6","MESSAGE":"kelolatest ping"}\n',
    );
    await pumpEventQueue();
    expect(got, hasLength(1));
    expect(got.single.message, 'kelolatest ping');
    await handle.cancel();
  });

  test('follow delivers a syslog logger line after the session is open', () async {
    final channel = _FakeFollowChannel();
    final got = <JournalEntry>[];
    final handle = JournalFollowHandle.bind(
      channel: channel,
      onEntry: got.add,
    );
    channel.addText(
      '2026-09-03T06:55:32.661499+00:00 east-worker-uat kelolatest: cobain 1788418532\n',
    );
    await pumpEventQueue();
    expect(got, hasLength(1));
    expect(got.single.message, 'cobain 1788418532');
    await handle.cancel();
  });

  test('follow drops a line already present by cursor or timestamp+message', () {
    const have = [
      JournalEntry(
        cursor: 'c1',
        realtimeUsec: '100',
        priority: 6,
        message: 'cobain 1',
      ),
    ];
    expect(
      shouldAcceptFollowEntry(
        const JournalEntry(
          cursor: 'c1',
          realtimeUsec: '200',
          priority: 6,
          message: 'other',
        ),
        have,
      ),
      isFalse,
    );
    expect(
      shouldAcceptFollowEntry(
        const JournalEntry(
          cursor: 'syslog:100:kelolatest:cobain 1',
          realtimeUsec: '100',
          priority: 6,
          message: 'cobain 1',
        ),
        have,
      ),
      isFalse,
    );
    expect(
      shouldAcceptFollowEntry(
        const JournalEntry(
          cursor: 'c2',
          realtimeUsec: '200',
          priority: 6,
          message: 'cobain 2',
        ),
        have,
      ),
      isTrue,
    );
  });

  test('remote stdout close notifies onClosed so LIVE can drop', () async {
    final channel = _FakeFollowChannel();
    var closed = false;
    JournalFollowHandle.bind(
      channel: channel,
      onEntry: (_) {},
      onClosed: () => closed = true,
    );
    await channel.close();
    await pumpEventQueue();
    expect(closed, isTrue);
  });

  test('pool startFollow uses a dedicated channel; cancel leaks none', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final channel = _FakeFollowChannel();
    final pool = SshSessionPool(
      repository: repo,
      signer: _BoomSigner(),
      hostKeys: HostKeyPolicy(repo),
      publicBlob: () => throw StateError('follow test must not open SSH'),
      followOpener: ({
        required Host host,
        required String command,
        UnknownHostKeyHandler? onUnknownHostKey,
      }) async {
        expect(command, contains('tail -n 0 -F /var/log/syslog'));
        return channel;
      },
    );

    final got = <JournalEntry>[];
    final handle = await pool.startJournalFollow(
      _host,
      facts: _facts,
      onEntry: got.add,
    );
    expect(pool.activeFollowCount, 1);
    expect(pool.hasActiveFollow(_host.id), isTrue);
    expect(identical(handle.channel, channel), isTrue);

    await handle.cancel();
    expect(channel.closed, isTrue);
    expect(pool.activeFollowCount, 0);
    expect(pool.hasActiveFollow(_host.id), isFalse);
  });

  test('pool disconnect cancels an open follow channel', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final channel = _FakeFollowChannel();
    final pool = SshSessionPool(
      repository: repo,
      signer: _BoomSigner(),
      hostKeys: HostKeyPolicy(repo),
      publicBlob: () => throw StateError('follow test must not open SSH'),
      followOpener: ({
        required Host host,
        required String command,
        UnknownHostKeyHandler? onUnknownHostKey,
      }) async =>
          channel,
    );

    await pool.startJournalFollow(_host, facts: _facts, onEntry: (_) {});
    expect(pool.activeFollowCount, 1);
    await pool.disconnect(_host.id);
    expect(channel.closed, isTrue);
    expect(pool.activeFollowCount, 0);
  });
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
    throw StateError('follow test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('follow test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
