import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/vault/vault.dart';
import 'package:kelola/domain/vault/vault_crypto.dart';
import 'package:kelola/domain/vault/vault_transport.dart';

void main() {
  test('newer vaultSchemaVersion is refused', () {
    expect(
      () => decodeVaultPlaintext({
        'vaultSchemaVersion': kVaultSchemaVersion + 1,
        'records': <Map<String, Object?>>[],
      }),
      throwsA(isA<VaultVersionUnsupported>()),
    );
  });

  test('unknown plaintext fields survive encode/decode', () {
    final plain = decodeVaultPlaintext({
      'vaultSchemaVersion': kVaultSchemaVersion,
      'deviceId': 'dev-a',
      'includeSecrets': false,
      'records': <Map<String, Object?>>[],
      'customFlag': 'keep-me',
    });
    expect(plain.extras['customFlag'], 'keep-me');
    expect(encodeVaultPlaintext(plain)['customFlag'], 'keep-me');
  });

  test('seal and open round-trip; wrong passphrase fails', () async {
    final plain = decodeVaultPlaintext({
      'vaultSchemaVersion': kVaultSchemaVersion,
      'deviceId': 'dev-a',
      'includeSecrets': false,
      'records': [
        vaultRecordJson(
          VaultRecord(
            id: 'h1',
            kind: VaultRecordKind.host,
            updatedAt: DateTime.utc(2026, 9, 27),
            deviceId: 'dev-a',
            payload: const {'alias': 'nas-01'},
          ),
        ),
      ],
    });
    final blob = await sealVault(
      plain,
      'correct-horse',
      params: VaultKdfParams.test,
    );
    final opened = await openVault(blob, 'correct-horse');
    expect(opened.records.single.payload['alias'], 'nas-01');
    await expectLater(
      openVault(blob, 'wrong'),
      throwsA(isA<VaultPassphraseException>()),
    );
  });

  test('default pack drops secrets and StrongBox material', () {
    final packed = packVaultRecords(
      records: [
        VaultRecord(
          id: 'h1',
          kind: VaultRecordKind.host,
          updatedAt: DateTime.utc(2026, 9, 27),
          deviceId: 'dev-a',
          payload: const {
            'alias': 'nas-01',
            'password': 'secret',
            'privateKey': 'BEGIN PRIVATE',
            'publicKeySpkiB64': 'abc',
          },
        ),
      ],
      deviceId: 'dev-a',
      includeSecrets: false,
    );
    final payload = packed.records.single.payload;
    expect(payload['alias'], 'nas-01');
    expect(payload.containsKey('password'), isFalse);
    expect(payload.containsKey('privateKey'), isFalse);
    expect(payload.containsKey('publicKeySpkiB64'), isFalse);
  });

  test('merge is last-write-wins with device-id tiebreak and tombstones', () {
    final older = VaultRecord(
      id: 'h1',
      kind: VaultRecordKind.host,
      updatedAt: DateTime.utc(2026, 1, 1),
      deviceId: 'dev-a',
      payload: const {'alias': 'old'},
    );
    final newer = VaultRecord(
      id: 'h1',
      kind: VaultRecordKind.host,
      updatedAt: DateTime.utc(2026, 9, 1),
      deviceId: 'dev-b',
      payload: const {'alias': 'new'},
    );
    final tieLocal = older.copyWith(
      updatedAt: DateTime.utc(2026, 9, 1),
      deviceId: 'dev-a',
    );
    final tieRemote = newer.copyWith(
      updatedAt: DateTime.utc(2026, 9, 1),
      deviceId: 'dev-z',
    );
    final added = VaultRecord(
      id: 'h2',
      kind: VaultRecordKind.host,
      updatedAt: DateTime.utc(2026, 9, 2),
      deviceId: 'dev-b',
      payload: const {'alias': 'edge'},
    );
    final tomb = VaultRecord(
      id: 'h3',
      kind: VaultRecordKind.host,
      updatedAt: DateTime.utc(2026, 9, 3),
      deviceId: 'dev-b',
      payload: const {},
      tombstone: true,
    );
    final localTombTarget = VaultRecord(
      id: 'h3',
      kind: VaultRecordKind.host,
      updatedAt: DateTime.utc(2026, 8, 1),
      deviceId: 'dev-a',
      payload: const {'alias': 'gone'},
    );

    final diff = diffVault(
      local: [older, localTombTarget],
      incoming: [newer, added, tomb],
    );
    expect(diff.added.map((r) => r.id), ['h2']);
    expect(diff.updated.single.payload['alias'], 'new');
    expect(diff.deleted.map((r) => r.id), ['h3']);

    final tie = diffVault(local: [tieLocal], incoming: [tieRemote]);
    expect(tie.updated.single.deviceId, 'dev-z');
  });

  test('file transport is free; lan and sftp require the unlock', () {
    expect(vaultTransportRequiresUnlock(VaultTransportKind.file), isFalse);
    expect(vaultTransportRequiresUnlock(VaultTransportKind.lan), isTrue);
    expect(vaultTransportRequiresUnlock(VaultTransportKind.sftp), isTrue);
    expect(kVaultSftpRelPath, '.kelola/vault.age');
  });

  test('env records encode without bumping vault schema', () {
    final record = VaultRecord(
      id: 'e1',
      kind: VaultRecordKind.env,
      updatedAt: DateTime.utc(2026, 9, 1),
      deviceId: 'dev-a',
      payload: const {
        'scope': 'tag',
        'scopeId': 'prod',
        'name': 'ROLE',
        'value': 'api',
      },
    );
    final json = vaultRecordJson(record);
    expect(json['kind'], 'env');
    expect(
      vaultRecordFromJson(Map<String, Object?>.from(json)).kind,
      VaultRecordKind.env,
    );
    expect(kVaultSchemaVersion, 1);
  });
}
