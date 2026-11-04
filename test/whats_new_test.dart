import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app_version.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/whats_new/whats_new.dart';
import 'package:kelola/presentation/whats_new_strings.dart';
import 'package:kelola/providers.dart';
import 'package:sqlite3/sqlite3.dart';

/// P-256 SubjectPublicKeyInfo (test-only key, no private half kept).
final _spki = base64Decode(
  'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEJLIt/km6xcwmq3qV7xcez3m1iuG8+XJ9'
  'wfdu4uEIXPX8vJRyUfHiSHLa8m+DTO/MsdfYHVUbhskB0C1+c8yAGg==',
);

class _FakeSigner implements HardwareSigner {
  var exists = false;

  @override
  Future<HardwareKey> generateKey(String alias) async {
    exists = true;
    return HardwareKey(
      alias: alias,
      publicKeySpki: Uint8List.fromList(_spki),
      backend: KeyBackend.strongbox,
      authRequired: false,
    );
  }

  @override
  Future<bool> keyExists(String alias) async => exists;

  @override
  Future<void> deleteKey(String alias) async => exists = false;

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async => Uint8List(0);

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {}
}

void main() {
  group('whatsNewDue', () {
    test('due once per version, not again after closing', () {
      expect(whatsNewDue(true, '1.0.0', '1.1.0'), isTrue);
      // Closing stores the version.
      expect(whatsNewDue(true, '1.1.0', '1.1.0'), isFalse);
      // The next version shows it again.
      expect(whatsNewDue(true, '1.1.0', '1.2.0'), isTrue);
    });

    test('due for upgraders from builds before the card (nothing saved)', () {
      expect(whatsNewDue(true, '', '1.1.0'), isTrue);
    });

    test('not due before onboarding', () {
      expect(whatsNewDue(false, '', '1.1.0'), isFalse);
      expect(whatsNewDue(false, '1.0.0', '1.1.0'), isFalse);
    });

    test('not due without a release version (debug, flutter run, tests)', () {
      expect(whatsNewDue(true, '', ''), isFalse);
      expect(whatsNewDue(true, '1.0.0', ''), isFalse);
    });
  });

  test('builds without --dart-define=APP_VERSION have no release version', () {
    expect(kelolaReleaseVersion, isEmpty);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(appVersionProvider), isEmpty);
  });

  test('strings notes equal docs/store/whatsnew/whatsnew-en-US', () {
    final raw = File('docs/store/whatsnew/whatsnew-en-US').readAsStringSync();
    expect(raw.length, lessThanOrEqualTo(500));
    final lines = raw
        .replaceAll('\r', '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    for (final l in lines) {
      expect(l, startsWith('- '), reason: 'one "- " line per point: $l');
    }
    expect(WhatsNewStrings.notes, [
      for (final l in lines) l.substring(2).trim(),
    ]);
    expect(WhatsNewStrings.notes, isNotEmpty);
    expect(WhatsNewStrings.notes.length, lessThanOrEqualTo(3));
    for (final n in WhatsNewStrings.notes) {
      expect(n.length, lessThanOrEqualTo(110), reason: 'keep notes short: $n');
    }
  });

  group('seenVersion setting', () {
    test('defaults to empty and persists', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final repo = HostRepository(db);
      expect(await repo.seenVersion(), '');
      await repo.setSeenVersion('1.1.0');
      expect(await HostRepository(db).seenVersion(), '1.1.0');
      // Other settings writes keep it.
      await repo.setWidgetEnabled(true);
      await repo.saveDeviceKey(blobB64: 'AAAA', backend: 'strongbox');
      expect(await repo.seenVersion(), '1.1.0');
    });

    test('schema 26 adds app_settings.seen_version for upgraders', () async {
      final raw = sqlite3.openInMemory();
      raw.execute('''
CREATE TABLE app_settings (
  id INTEGER NOT NULL PRIMARY KEY,
  last_host_id TEXT NULL,
  public_key_spki_b64 TEXT NULL
);
''');
      raw.execute(
        "INSERT INTO app_settings (id, public_key_spki_b64) VALUES (1, 'AAAA')",
      );
      raw.execute('PRAGMA user_version = 25');
      final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], db.schemaVersion);
      final cols = await db
          .customSelect('PRAGMA table_info(app_settings)')
          .get();
      expect(
        cols.map((r) => r.read<String>('name')).contains('seen_version'),
        isTrue,
      );
      final row = await db
          .customSelect('SELECT seen_version FROM app_settings WHERE id = 1')
          .getSingle();
      expect(row.read<String>('seen_version'), '');
    });
  });

  group('whatsNewProvider', () {
    ProviderContainer containerFor(
      KelolaDatabase db,
      String version, {
      HardwareSigner? signer,
    }) {
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          appVersionProvider.overrideWithValue(version),
          if (signer != null) hardwareSignerProvider.overrideWithValue(signer),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('fresh install: first-run setup marks the version seen', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final c = containerFor(db, '1.1.0', signer: _FakeSigner());
      expect(await c.read(whatsNewProvider.future), isFalse);

      await c.read(enrollmentProvider.notifier).ensureKey();

      expect(await HostRepository(db).seenVersion(), '1.1.0');
      expect(await c.read(whatsNewProvider.future), isFalse);
    });

    test(
      'regenerating the key on an onboarded install keeps the card due',
      () async {
        final db = KelolaDatabase.memory();
        addTearDown(db.close);
        final repo = HostRepository(db);
        await repo.saveDeviceKey(blobB64: 'AAAA', backend: 'strongbox');
        // Key row stored but keystore lost it: regenerated, not first run.
        final c = containerFor(db, '1.1.0', signer: _FakeSigner());
        await c.read(enrollmentProvider.notifier).ensureKey();
        expect(await repo.seenVersion(), '');
        expect(await c.read(whatsNewProvider.future), isTrue);
      },
    );

    test('debug build: first-run setup stores nothing', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final c = containerFor(db, '', signer: _FakeSigner());
      await c.read(enrollmentProvider.notifier).ensureKey();
      expect(await HostRepository(db).seenVersion(), '');
      expect(await c.read(whatsNewProvider.future), isFalse);
    });

    test('upgrader sees it once; dismiss persists across restarts', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      await HostRepository(db)
          .saveDeviceKey(blobB64: 'AAAA', backend: 'strongbox');
      final first = containerFor(db, '1.1.0');
      expect(await first.read(whatsNewProvider.future), isTrue);
      await first.read(whatsNewProvider.notifier).dismiss();
      expect(first.read(whatsNewProvider).value, isFalse);
      expect(await HostRepository(db).seenVersion(), '1.1.0');

      final restart = containerFor(db, '1.1.0');
      expect(await restart.read(whatsNewProvider.future), isFalse);

      final nextRelease = containerFor(db, '1.2.0');
      expect(await nextRelease.read(whatsNewProvider.future), isTrue);
    });
  });
}
