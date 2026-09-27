const int kVaultSchemaVersion = 1;

const Set<String> kVaultSecretKeys = {
  'password',
  'privateKey',
  'pem',
  'apiKey',
  'publicKeySpkiB64',
};

enum VaultRecordKind {
  host,
  snippet,
  hostTag,
  hostKey,
  tunnel,
  pref,
  env,
  tombstone,
}

class VaultVersionUnsupported implements Exception {
  VaultVersionUnsupported(this.version);

  final int version;

  @override
  String toString() => 'Vault schema $version is newer than $kVaultSchemaVersion';
}

class VaultRecord {
  const VaultRecord({
    required this.id,
    required this.kind,
    required this.updatedAt,
    required this.deviceId,
    required this.payload,
    this.tombstone = false,
  });

  final String id;
  final VaultRecordKind kind;
  final DateTime updatedAt;
  final String deviceId;
  final Map<String, Object?> payload;
  final bool tombstone;

  VaultRecord copyWith({
    DateTime? updatedAt,
    String? deviceId,
    Map<String, Object?>? payload,
    bool? tombstone,
  }) {
    return VaultRecord(
      id: id,
      kind: kind,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
      payload: payload ?? this.payload,
      tombstone: tombstone ?? this.tombstone,
    );
  }
}

class VaultPlaintext {
  const VaultPlaintext({
    required this.deviceId,
    required this.includeSecrets,
    required this.records,
    this.extras = const {},
  });

  final String deviceId;
  final bool includeSecrets;
  final List<VaultRecord> records;
  final Map<String, Object?> extras;
}

class VaultDiff {
  const VaultDiff({
    required this.added,
    required this.updated,
    required this.deleted,
  });

  final List<VaultRecord> added;
  final List<VaultRecord> updated;
  final List<VaultRecord> deleted;

  String get summary =>
      '${added.length} new, ${updated.length} updated, ${deleted.length} deleted';
}

Map<String, Object?> vaultRecordJson(VaultRecord record) {
  return {
    'id': record.id,
    'kind': record.kind.name,
    'updatedAt': record.updatedAt.toUtc().toIso8601String(),
    'deviceId': record.deviceId,
    'tombstone': record.tombstone,
    'payload': record.payload,
  };
}

VaultRecord vaultRecordFromJson(Map<String, Object?> json) {
  final payloadRaw = json['payload'];
  return VaultRecord(
    id: json['id'] as String? ?? '',
    kind: VaultRecordKind.values.byName(json['kind'] as String? ?? 'host'),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    deviceId: json['deviceId'] as String? ?? '',
    tombstone: json['tombstone'] as bool? ?? false,
    payload: payloadRaw is Map
        ? Map<String, Object?>.from(payloadRaw)
        : const {},
  );
}

VaultPlaintext decodeVaultPlaintext(Map<String, Object?> json) {
  final version = json['vaultSchemaVersion'] as int? ?? 0;
  if (version > kVaultSchemaVersion) {
    throw VaultVersionUnsupported(version);
  }
  final extras = Map<String, Object?>.from(json)
    ..remove('vaultSchemaVersion')
    ..remove('deviceId')
    ..remove('includeSecrets')
    ..remove('records');
  final rawRecords = json['records'];
  return VaultPlaintext(
    deviceId: json['deviceId'] as String? ?? '',
    includeSecrets: json['includeSecrets'] as bool? ?? false,
    records: [
      if (rawRecords is List)
        for (final item in rawRecords)
          if (item is Map) vaultRecordFromJson(Map<String, Object?>.from(item)),
    ],
    extras: extras,
  );
}

Map<String, Object?> encodeVaultPlaintext(VaultPlaintext plain) {
  return {
    'vaultSchemaVersion': kVaultSchemaVersion,
    'deviceId': plain.deviceId,
    'includeSecrets': plain.includeSecrets,
    'records': [for (final record in plain.records) vaultRecordJson(record)],
    ...plain.extras,
  };
}

VaultPlaintext packVaultRecords({
  required List<VaultRecord> records,
  required String deviceId,
  required bool includeSecrets,
  Map<String, Object?> extras = const {},
}) {
  return VaultPlaintext(
    deviceId: deviceId,
    includeSecrets: includeSecrets,
    extras: extras,
    records: [
      for (final record in records)
        record.copyWith(
          payload: includeSecrets
              ? record.payload
              : {
                  for (final entry in record.payload.entries)
                    if (!kVaultSecretKeys.contains(entry.key)) entry.key: entry.value,
                },
        ),
    ],
  );
}

int _compareRecords(VaultRecord a, VaultRecord b) {
  final byTime = a.updatedAt.compareTo(b.updatedAt);
  if (byTime != 0) {
    return byTime;
  }
  return a.deviceId.compareTo(b.deviceId);
}

VaultDiff diffVault({
  required List<VaultRecord> local,
  required List<VaultRecord> incoming,
}) {
  final localById = {for (final record in local) record.id: record};
  final added = <VaultRecord>[];
  final updated = <VaultRecord>[];
  final deleted = <VaultRecord>[];
  for (final next in incoming) {
    final current = localById[next.id];
    if (next.tombstone) {
      if (current != null &&
          !current.tombstone &&
          _compareRecords(next, current) > 0) {
        deleted.add(next);
      }
      continue;
    }
    if (current == null || current.tombstone) {
      added.add(next);
      continue;
    }
    if (_compareRecords(next, current) > 0) {
      updated.add(next);
    }
  }
  return VaultDiff(added: added, updated: updated, deleted: deleted);
}
