// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $HostsTable extends Hosts with TableInfo<$HostsTable, HostRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HostsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(22),
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyAliasMeta = const VerificationMeta(
    'keyAlias',
  );
  @override
  late final GeneratedColumn<String> keyAlias = GeneratedColumn<String>(
    'key_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jumpHostIdMeta = const VerificationMeta(
    'jumpHostId',
  );
  @override
  late final GeneratedColumn<String> jumpHostId = GeneratedColumn<String>(
    'jump_host_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readOnlyMeta = const VerificationMeta(
    'readOnly',
  );
  @override
  late final GeneratedColumn<bool> readOnly = GeneratedColumn<bool>(
    'read_only',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("read_only" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastRttMsMeta = const VerificationMeta(
    'lastRttMs',
  );
  @override
  late final GeneratedColumn<int> lastRttMs = GeneratedColumn<int>(
    'last_rtt_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attentionMeta = const VerificationMeta(
    'attention',
  );
  @override
  late final GeneratedColumn<String> attention = GeneratedColumn<String>(
    'attention',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _failedUnitCountMeta = const VerificationMeta(
    'failedUnitCount',
  );
  @override
  late final GeneratedColumn<int> failedUnitCount = GeneratedColumn<int>(
    'failed_unit_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _diskRootPercentMeta = const VerificationMeta(
    'diskRootPercent',
  );
  @override
  late final GeneratedColumn<int> diskRootPercent = GeneratedColumn<int>(
    'disk_root_percent',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attentionAtMeta = const VerificationMeta(
    'attentionAt',
  );
  @override
  late final GeneratedColumn<DateTime> attentionAt = GeneratedColumn<DateTime>(
    'attention_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sudoNeedsPasswordMeta = const VerificationMeta(
    'sudoNeedsPassword',
  );
  @override
  late final GeneratedColumn<bool> sudoNeedsPassword = GeneratedColumn<bool>(
    'sudo_needs_password',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sudo_needs_password" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    alias,
    address,
    port,
    username,
    keyAlias,
    jumpHostId,
    readOnly,
    sortOrder,
    note,
    lastRttMs,
    attention,
    failedUnitCount,
    diskRootPercent,
    attentionAt,
    lastSeenAt,
    createdAt,
    sudoNeedsPassword,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hosts';
  @override
  VerificationContext validateIntegrity(
    Insertable<HostRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasMeta);
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('key_alias')) {
      context.handle(
        _keyAliasMeta,
        keyAlias.isAcceptableOrUnknown(data['key_alias']!, _keyAliasMeta),
      );
    } else if (isInserting) {
      context.missing(_keyAliasMeta);
    }
    if (data.containsKey('jump_host_id')) {
      context.handle(
        _jumpHostIdMeta,
        jumpHostId.isAcceptableOrUnknown(
          data['jump_host_id']!,
          _jumpHostIdMeta,
        ),
      );
    }
    if (data.containsKey('read_only')) {
      context.handle(
        _readOnlyMeta,
        readOnly.isAcceptableOrUnknown(data['read_only']!, _readOnlyMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('last_rtt_ms')) {
      context.handle(
        _lastRttMsMeta,
        lastRttMs.isAcceptableOrUnknown(data['last_rtt_ms']!, _lastRttMsMeta),
      );
    }
    if (data.containsKey('attention')) {
      context.handle(
        _attentionMeta,
        attention.isAcceptableOrUnknown(data['attention']!, _attentionMeta),
      );
    }
    if (data.containsKey('failed_unit_count')) {
      context.handle(
        _failedUnitCountMeta,
        failedUnitCount.isAcceptableOrUnknown(
          data['failed_unit_count']!,
          _failedUnitCountMeta,
        ),
      );
    }
    if (data.containsKey('disk_root_percent')) {
      context.handle(
        _diskRootPercentMeta,
        diskRootPercent.isAcceptableOrUnknown(
          data['disk_root_percent']!,
          _diskRootPercentMeta,
        ),
      );
    }
    if (data.containsKey('attention_at')) {
      context.handle(
        _attentionAtMeta,
        attentionAt.isAcceptableOrUnknown(
          data['attention_at']!,
          _attentionAtMeta,
        ),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('sudo_needs_password')) {
      context.handle(
        _sudoNeedsPasswordMeta,
        sudoNeedsPassword.isAcceptableOrUnknown(
          data['sudo_needs_password']!,
          _sudoNeedsPasswordMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HostRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HostRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      keyAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_alias'],
      )!,
      jumpHostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jump_host_id'],
      ),
      readOnly: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}read_only'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      lastRttMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_rtt_ms'],
      ),
      attention: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attention'],
      )!,
      failedUnitCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failed_unit_count'],
      ),
      diskRootPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disk_root_percent'],
      ),
      attentionAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}attention_at'],
      ),
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      sudoNeedsPassword: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sudo_needs_password'],
      )!,
    );
  }

  @override
  $HostsTable createAlias(String alias) {
    return $HostsTable(attachedDatabase, alias);
  }
}

class HostRow extends DataClass implements Insertable<HostRow> {
  final String id;
  final String alias;
  final String address;
  final int port;
  final String username;
  final String keyAlias;
  final String? jumpHostId;
  final bool readOnly;
  final int sortOrder;
  final String? note;
  final int? lastRttMs;
  final String attention;
  final int? failedUnitCount;
  final int? diskRootPercent;
  final DateTime? attentionAt;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final bool sudoNeedsPassword;
  const HostRow({
    required this.id,
    required this.alias,
    required this.address,
    required this.port,
    required this.username,
    required this.keyAlias,
    this.jumpHostId,
    required this.readOnly,
    required this.sortOrder,
    this.note,
    this.lastRttMs,
    required this.attention,
    this.failedUnitCount,
    this.diskRootPercent,
    this.attentionAt,
    this.lastSeenAt,
    required this.createdAt,
    required this.sudoNeedsPassword,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['alias'] = Variable<String>(alias);
    map['address'] = Variable<String>(address);
    map['port'] = Variable<int>(port);
    map['username'] = Variable<String>(username);
    map['key_alias'] = Variable<String>(keyAlias);
    if (!nullToAbsent || jumpHostId != null) {
      map['jump_host_id'] = Variable<String>(jumpHostId);
    }
    map['read_only'] = Variable<bool>(readOnly);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || lastRttMs != null) {
      map['last_rtt_ms'] = Variable<int>(lastRttMs);
    }
    map['attention'] = Variable<String>(attention);
    if (!nullToAbsent || failedUnitCount != null) {
      map['failed_unit_count'] = Variable<int>(failedUnitCount);
    }
    if (!nullToAbsent || diskRootPercent != null) {
      map['disk_root_percent'] = Variable<int>(diskRootPercent);
    }
    if (!nullToAbsent || attentionAt != null) {
      map['attention_at'] = Variable<DateTime>(attentionAt);
    }
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['sudo_needs_password'] = Variable<bool>(sudoNeedsPassword);
    return map;
  }

  HostsCompanion toCompanion(bool nullToAbsent) {
    return HostsCompanion(
      id: Value(id),
      alias: Value(alias),
      address: Value(address),
      port: Value(port),
      username: Value(username),
      keyAlias: Value(keyAlias),
      jumpHostId: jumpHostId == null && nullToAbsent
          ? const Value.absent()
          : Value(jumpHostId),
      readOnly: Value(readOnly),
      sortOrder: Value(sortOrder),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      lastRttMs: lastRttMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRttMs),
      attention: Value(attention),
      failedUnitCount: failedUnitCount == null && nullToAbsent
          ? const Value.absent()
          : Value(failedUnitCount),
      diskRootPercent: diskRootPercent == null && nullToAbsent
          ? const Value.absent()
          : Value(diskRootPercent),
      attentionAt: attentionAt == null && nullToAbsent
          ? const Value.absent()
          : Value(attentionAt),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      createdAt: Value(createdAt),
      sudoNeedsPassword: Value(sudoNeedsPassword),
    );
  }

  factory HostRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HostRow(
      id: serializer.fromJson<String>(json['id']),
      alias: serializer.fromJson<String>(json['alias']),
      address: serializer.fromJson<String>(json['address']),
      port: serializer.fromJson<int>(json['port']),
      username: serializer.fromJson<String>(json['username']),
      keyAlias: serializer.fromJson<String>(json['keyAlias']),
      jumpHostId: serializer.fromJson<String?>(json['jumpHostId']),
      readOnly: serializer.fromJson<bool>(json['readOnly']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      note: serializer.fromJson<String?>(json['note']),
      lastRttMs: serializer.fromJson<int?>(json['lastRttMs']),
      attention: serializer.fromJson<String>(json['attention']),
      failedUnitCount: serializer.fromJson<int?>(json['failedUnitCount']),
      diskRootPercent: serializer.fromJson<int?>(json['diskRootPercent']),
      attentionAt: serializer.fromJson<DateTime?>(json['attentionAt']),
      lastSeenAt: serializer.fromJson<DateTime?>(json['lastSeenAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sudoNeedsPassword: serializer.fromJson<bool>(json['sudoNeedsPassword']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'alias': serializer.toJson<String>(alias),
      'address': serializer.toJson<String>(address),
      'port': serializer.toJson<int>(port),
      'username': serializer.toJson<String>(username),
      'keyAlias': serializer.toJson<String>(keyAlias),
      'jumpHostId': serializer.toJson<String?>(jumpHostId),
      'readOnly': serializer.toJson<bool>(readOnly),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'note': serializer.toJson<String?>(note),
      'lastRttMs': serializer.toJson<int?>(lastRttMs),
      'attention': serializer.toJson<String>(attention),
      'failedUnitCount': serializer.toJson<int?>(failedUnitCount),
      'diskRootPercent': serializer.toJson<int?>(diskRootPercent),
      'attentionAt': serializer.toJson<DateTime?>(attentionAt),
      'lastSeenAt': serializer.toJson<DateTime?>(lastSeenAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sudoNeedsPassword': serializer.toJson<bool>(sudoNeedsPassword),
    };
  }

  HostRow copyWith({
    String? id,
    String? alias,
    String? address,
    int? port,
    String? username,
    String? keyAlias,
    Value<String?> jumpHostId = const Value.absent(),
    bool? readOnly,
    int? sortOrder,
    Value<String?> note = const Value.absent(),
    Value<int?> lastRttMs = const Value.absent(),
    String? attention,
    Value<int?> failedUnitCount = const Value.absent(),
    Value<int?> diskRootPercent = const Value.absent(),
    Value<DateTime?> attentionAt = const Value.absent(),
    Value<DateTime?> lastSeenAt = const Value.absent(),
    DateTime? createdAt,
    bool? sudoNeedsPassword,
  }) => HostRow(
    id: id ?? this.id,
    alias: alias ?? this.alias,
    address: address ?? this.address,
    port: port ?? this.port,
    username: username ?? this.username,
    keyAlias: keyAlias ?? this.keyAlias,
    jumpHostId: jumpHostId.present ? jumpHostId.value : this.jumpHostId,
    readOnly: readOnly ?? this.readOnly,
    sortOrder: sortOrder ?? this.sortOrder,
    note: note.present ? note.value : this.note,
    lastRttMs: lastRttMs.present ? lastRttMs.value : this.lastRttMs,
    attention: attention ?? this.attention,
    failedUnitCount: failedUnitCount.present
        ? failedUnitCount.value
        : this.failedUnitCount,
    diskRootPercent: diskRootPercent.present
        ? diskRootPercent.value
        : this.diskRootPercent,
    attentionAt: attentionAt.present ? attentionAt.value : this.attentionAt,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    createdAt: createdAt ?? this.createdAt,
    sudoNeedsPassword: sudoNeedsPassword ?? this.sudoNeedsPassword,
  );
  HostRow copyWithCompanion(HostsCompanion data) {
    return HostRow(
      id: data.id.present ? data.id.value : this.id,
      alias: data.alias.present ? data.alias.value : this.alias,
      address: data.address.present ? data.address.value : this.address,
      port: data.port.present ? data.port.value : this.port,
      username: data.username.present ? data.username.value : this.username,
      keyAlias: data.keyAlias.present ? data.keyAlias.value : this.keyAlias,
      jumpHostId: data.jumpHostId.present
          ? data.jumpHostId.value
          : this.jumpHostId,
      readOnly: data.readOnly.present ? data.readOnly.value : this.readOnly,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      note: data.note.present ? data.note.value : this.note,
      lastRttMs: data.lastRttMs.present ? data.lastRttMs.value : this.lastRttMs,
      attention: data.attention.present ? data.attention.value : this.attention,
      failedUnitCount: data.failedUnitCount.present
          ? data.failedUnitCount.value
          : this.failedUnitCount,
      diskRootPercent: data.diskRootPercent.present
          ? data.diskRootPercent.value
          : this.diskRootPercent,
      attentionAt: data.attentionAt.present
          ? data.attentionAt.value
          : this.attentionAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sudoNeedsPassword: data.sudoNeedsPassword.present
          ? data.sudoNeedsPassword.value
          : this.sudoNeedsPassword,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HostRow(')
          ..write('id: $id, ')
          ..write('alias: $alias, ')
          ..write('address: $address, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('keyAlias: $keyAlias, ')
          ..write('jumpHostId: $jumpHostId, ')
          ..write('readOnly: $readOnly, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('note: $note, ')
          ..write('lastRttMs: $lastRttMs, ')
          ..write('attention: $attention, ')
          ..write('failedUnitCount: $failedUnitCount, ')
          ..write('diskRootPercent: $diskRootPercent, ')
          ..write('attentionAt: $attentionAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('sudoNeedsPassword: $sudoNeedsPassword')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    alias,
    address,
    port,
    username,
    keyAlias,
    jumpHostId,
    readOnly,
    sortOrder,
    note,
    lastRttMs,
    attention,
    failedUnitCount,
    diskRootPercent,
    attentionAt,
    lastSeenAt,
    createdAt,
    sudoNeedsPassword,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostRow &&
          other.id == this.id &&
          other.alias == this.alias &&
          other.address == this.address &&
          other.port == this.port &&
          other.username == this.username &&
          other.keyAlias == this.keyAlias &&
          other.jumpHostId == this.jumpHostId &&
          other.readOnly == this.readOnly &&
          other.sortOrder == this.sortOrder &&
          other.note == this.note &&
          other.lastRttMs == this.lastRttMs &&
          other.attention == this.attention &&
          other.failedUnitCount == this.failedUnitCount &&
          other.diskRootPercent == this.diskRootPercent &&
          other.attentionAt == this.attentionAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.createdAt == this.createdAt &&
          other.sudoNeedsPassword == this.sudoNeedsPassword);
}

class HostsCompanion extends UpdateCompanion<HostRow> {
  final Value<String> id;
  final Value<String> alias;
  final Value<String> address;
  final Value<int> port;
  final Value<String> username;
  final Value<String> keyAlias;
  final Value<String?> jumpHostId;
  final Value<bool> readOnly;
  final Value<int> sortOrder;
  final Value<String?> note;
  final Value<int?> lastRttMs;
  final Value<String> attention;
  final Value<int?> failedUnitCount;
  final Value<int?> diskRootPercent;
  final Value<DateTime?> attentionAt;
  final Value<DateTime?> lastSeenAt;
  final Value<DateTime> createdAt;
  final Value<bool> sudoNeedsPassword;
  final Value<int> rowid;
  const HostsCompanion({
    this.id = const Value.absent(),
    this.alias = const Value.absent(),
    this.address = const Value.absent(),
    this.port = const Value.absent(),
    this.username = const Value.absent(),
    this.keyAlias = const Value.absent(),
    this.jumpHostId = const Value.absent(),
    this.readOnly = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.note = const Value.absent(),
    this.lastRttMs = const Value.absent(),
    this.attention = const Value.absent(),
    this.failedUnitCount = const Value.absent(),
    this.diskRootPercent = const Value.absent(),
    this.attentionAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sudoNeedsPassword = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HostsCompanion.insert({
    required String id,
    required String alias,
    required String address,
    this.port = const Value.absent(),
    required String username,
    required String keyAlias,
    this.jumpHostId = const Value.absent(),
    this.readOnly = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.note = const Value.absent(),
    this.lastRttMs = const Value.absent(),
    this.attention = const Value.absent(),
    this.failedUnitCount = const Value.absent(),
    this.diskRootPercent = const Value.absent(),
    this.attentionAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    required DateTime createdAt,
    this.sudoNeedsPassword = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       alias = Value(alias),
       address = Value(address),
       username = Value(username),
       keyAlias = Value(keyAlias),
       createdAt = Value(createdAt);
  static Insertable<HostRow> custom({
    Expression<String>? id,
    Expression<String>? alias,
    Expression<String>? address,
    Expression<int>? port,
    Expression<String>? username,
    Expression<String>? keyAlias,
    Expression<String>? jumpHostId,
    Expression<bool>? readOnly,
    Expression<int>? sortOrder,
    Expression<String>? note,
    Expression<int>? lastRttMs,
    Expression<String>? attention,
    Expression<int>? failedUnitCount,
    Expression<int>? diskRootPercent,
    Expression<DateTime>? attentionAt,
    Expression<DateTime>? lastSeenAt,
    Expression<DateTime>? createdAt,
    Expression<bool>? sudoNeedsPassword,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (alias != null) 'alias': alias,
      if (address != null) 'address': address,
      if (port != null) 'port': port,
      if (username != null) 'username': username,
      if (keyAlias != null) 'key_alias': keyAlias,
      if (jumpHostId != null) 'jump_host_id': jumpHostId,
      if (readOnly != null) 'read_only': readOnly,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (note != null) 'note': note,
      if (lastRttMs != null) 'last_rtt_ms': lastRttMs,
      if (attention != null) 'attention': attention,
      if (failedUnitCount != null) 'failed_unit_count': failedUnitCount,
      if (diskRootPercent != null) 'disk_root_percent': diskRootPercent,
      if (attentionAt != null) 'attention_at': attentionAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (createdAt != null) 'created_at': createdAt,
      if (sudoNeedsPassword != null) 'sudo_needs_password': sudoNeedsPassword,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HostsCompanion copyWith({
    Value<String>? id,
    Value<String>? alias,
    Value<String>? address,
    Value<int>? port,
    Value<String>? username,
    Value<String>? keyAlias,
    Value<String?>? jumpHostId,
    Value<bool>? readOnly,
    Value<int>? sortOrder,
    Value<String?>? note,
    Value<int?>? lastRttMs,
    Value<String>? attention,
    Value<int?>? failedUnitCount,
    Value<int?>? diskRootPercent,
    Value<DateTime?>? attentionAt,
    Value<DateTime?>? lastSeenAt,
    Value<DateTime>? createdAt,
    Value<bool>? sudoNeedsPassword,
    Value<int>? rowid,
  }) {
    return HostsCompanion(
      id: id ?? this.id,
      alias: alias ?? this.alias,
      address: address ?? this.address,
      port: port ?? this.port,
      username: username ?? this.username,
      keyAlias: keyAlias ?? this.keyAlias,
      jumpHostId: jumpHostId ?? this.jumpHostId,
      readOnly: readOnly ?? this.readOnly,
      sortOrder: sortOrder ?? this.sortOrder,
      note: note ?? this.note,
      lastRttMs: lastRttMs ?? this.lastRttMs,
      attention: attention ?? this.attention,
      failedUnitCount: failedUnitCount ?? this.failedUnitCount,
      diskRootPercent: diskRootPercent ?? this.diskRootPercent,
      attentionAt: attentionAt ?? this.attentionAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
      sudoNeedsPassword: sudoNeedsPassword ?? this.sudoNeedsPassword,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (keyAlias.present) {
      map['key_alias'] = Variable<String>(keyAlias.value);
    }
    if (jumpHostId.present) {
      map['jump_host_id'] = Variable<String>(jumpHostId.value);
    }
    if (readOnly.present) {
      map['read_only'] = Variable<bool>(readOnly.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (lastRttMs.present) {
      map['last_rtt_ms'] = Variable<int>(lastRttMs.value);
    }
    if (attention.present) {
      map['attention'] = Variable<String>(attention.value);
    }
    if (failedUnitCount.present) {
      map['failed_unit_count'] = Variable<int>(failedUnitCount.value);
    }
    if (diskRootPercent.present) {
      map['disk_root_percent'] = Variable<int>(diskRootPercent.value);
    }
    if (attentionAt.present) {
      map['attention_at'] = Variable<DateTime>(attentionAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sudoNeedsPassword.present) {
      map['sudo_needs_password'] = Variable<bool>(sudoNeedsPassword.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HostsCompanion(')
          ..write('id: $id, ')
          ..write('alias: $alias, ')
          ..write('address: $address, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('keyAlias: $keyAlias, ')
          ..write('jumpHostId: $jumpHostId, ')
          ..write('readOnly: $readOnly, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('note: $note, ')
          ..write('lastRttMs: $lastRttMs, ')
          ..write('attention: $attention, ')
          ..write('failedUnitCount: $failedUnitCount, ')
          ..write('diskRootPercent: $diskRootPercent, ')
          ..write('attentionAt: $attentionAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('sudoNeedsPassword: $sudoNeedsPassword, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HostKeysTable extends HostKeys
    with TableInfo<$HostKeysTable, HostKeyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HostKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _algorithmMeta = const VerificationMeta(
    'algorithm',
  );
  @override
  late final GeneratedColumn<String> algorithm = GeneratedColumn<String>(
    'algorithm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinnedAtMeta = const VerificationMeta(
    'pinnedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pinnedAt = GeneratedColumn<DateTime>(
    'pinned_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    hostId,
    algorithm,
    fingerprint,
    pinnedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'host_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<HostKeyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('algorithm')) {
      context.handle(
        _algorithmMeta,
        algorithm.isAcceptableOrUnknown(data['algorithm']!, _algorithmMeta),
      );
    } else if (isInserting) {
      context.missing(_algorithmMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('pinned_at')) {
      context.handle(
        _pinnedAtMeta,
        pinnedAt.isAcceptableOrUnknown(data['pinned_at']!, _pinnedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pinnedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hostId};
  @override
  HostKeyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HostKeyRow(
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      algorithm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}algorithm'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      pinnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}pinned_at'],
      )!,
    );
  }

  @override
  $HostKeysTable createAlias(String alias) {
    return $HostKeysTable(attachedDatabase, alias);
  }
}

class HostKeyRow extends DataClass implements Insertable<HostKeyRow> {
  final String hostId;
  final String algorithm;
  final String fingerprint;
  final DateTime pinnedAt;
  const HostKeyRow({
    required this.hostId,
    required this.algorithm,
    required this.fingerprint,
    required this.pinnedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['host_id'] = Variable<String>(hostId);
    map['algorithm'] = Variable<String>(algorithm);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['pinned_at'] = Variable<DateTime>(pinnedAt);
    return map;
  }

  HostKeysCompanion toCompanion(bool nullToAbsent) {
    return HostKeysCompanion(
      hostId: Value(hostId),
      algorithm: Value(algorithm),
      fingerprint: Value(fingerprint),
      pinnedAt: Value(pinnedAt),
    );
  }

  factory HostKeyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HostKeyRow(
      hostId: serializer.fromJson<String>(json['hostId']),
      algorithm: serializer.fromJson<String>(json['algorithm']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      pinnedAt: serializer.fromJson<DateTime>(json['pinnedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hostId': serializer.toJson<String>(hostId),
      'algorithm': serializer.toJson<String>(algorithm),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'pinnedAt': serializer.toJson<DateTime>(pinnedAt),
    };
  }

  HostKeyRow copyWith({
    String? hostId,
    String? algorithm,
    String? fingerprint,
    DateTime? pinnedAt,
  }) => HostKeyRow(
    hostId: hostId ?? this.hostId,
    algorithm: algorithm ?? this.algorithm,
    fingerprint: fingerprint ?? this.fingerprint,
    pinnedAt: pinnedAt ?? this.pinnedAt,
  );
  HostKeyRow copyWithCompanion(HostKeysCompanion data) {
    return HostKeyRow(
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      algorithm: data.algorithm.present ? data.algorithm.value : this.algorithm,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HostKeyRow(')
          ..write('hostId: $hostId, ')
          ..write('algorithm: $algorithm, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('pinnedAt: $pinnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(hostId, algorithm, fingerprint, pinnedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostKeyRow &&
          other.hostId == this.hostId &&
          other.algorithm == this.algorithm &&
          other.fingerprint == this.fingerprint &&
          other.pinnedAt == this.pinnedAt);
}

class HostKeysCompanion extends UpdateCompanion<HostKeyRow> {
  final Value<String> hostId;
  final Value<String> algorithm;
  final Value<String> fingerprint;
  final Value<DateTime> pinnedAt;
  final Value<int> rowid;
  const HostKeysCompanion({
    this.hostId = const Value.absent(),
    this.algorithm = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HostKeysCompanion.insert({
    required String hostId,
    required String algorithm,
    required String fingerprint,
    required DateTime pinnedAt,
    this.rowid = const Value.absent(),
  }) : hostId = Value(hostId),
       algorithm = Value(algorithm),
       fingerprint = Value(fingerprint),
       pinnedAt = Value(pinnedAt);
  static Insertable<HostKeyRow> custom({
    Expression<String>? hostId,
    Expression<String>? algorithm,
    Expression<String>? fingerprint,
    Expression<DateTime>? pinnedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (hostId != null) 'host_id': hostId,
      if (algorithm != null) 'algorithm': algorithm,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HostKeysCompanion copyWith({
    Value<String>? hostId,
    Value<String>? algorithm,
    Value<String>? fingerprint,
    Value<DateTime>? pinnedAt,
    Value<int>? rowid,
  }) {
    return HostKeysCompanion(
      hostId: hostId ?? this.hostId,
      algorithm: algorithm ?? this.algorithm,
      fingerprint: fingerprint ?? this.fingerprint,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (algorithm.present) {
      map['algorithm'] = Variable<String>(algorithm.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<DateTime>(pinnedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HostKeysCompanion(')
          ..write('hostId: $hostId, ')
          ..write('algorithm: $algorithm, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedFactsTable extends CachedFacts
    with TableInfo<$CachedFactsTable, CachedFactsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedFactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _osIdMeta = const VerificationMeta('osId');
  @override
  late final GeneratedColumn<String> osId = GeneratedColumn<String>(
    'os_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _osVersionIdMeta = const VerificationMeta(
    'osVersionId',
  );
  @override
  late final GeneratedColumn<String> osVersionId = GeneratedColumn<String>(
    'os_version_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _prettyNameMeta = const VerificationMeta(
    'prettyName',
  );
  @override
  late final GeneratedColumn<String> prettyName = GeneratedColumn<String>(
    'pretty_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _initSystemMeta = const VerificationMeta(
    'initSystem',
  );
  @override
  late final GeneratedColumn<String> initSystem = GeneratedColumn<String>(
    'init_system',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _systemdVersionMeta = const VerificationMeta(
    'systemdVersion',
  );
  @override
  late final GeneratedColumn<int> systemdVersion = GeneratedColumn<int>(
    'systemd_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pkgMeta = const VerificationMeta('pkg');
  @override
  late final GeneratedColumn<String> pkg = GeneratedColumn<String>(
    'pkg',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fwMeta = const VerificationMeta('fw');
  @override
  late final GeneratedColumn<String> fw = GeneratedColumn<String>(
    'fw',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hasJournaldMeta = const VerificationMeta(
    'hasJournald',
  );
  @override
  late final GeneratedColumn<bool> hasJournald = GeneratedColumn<bool>(
    'has_journald',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_journald" IN (0, 1))',
    ),
  );
  static const VerificationMeta _journalReadableMeta = const VerificationMeta(
    'journalReadable',
  );
  @override
  late final GeneratedColumn<bool> journalReadable = GeneratedColumn<bool>(
    'journal_readable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("journal_readable" IN (0, 1))',
    ),
  );
  static const VerificationMeta _archMeta = const VerificationMeta('arch');
  @override
  late final GeneratedColumn<String> arch = GeneratedColumn<String>(
    'arch',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _discoveredAtMeta = const VerificationMeta(
    'discoveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> discoveredAt = GeneratedColumn<DateTime>(
    'discovered_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    hostId,
    osId,
    osVersionId,
    prettyName,
    initSystem,
    systemdVersion,
    pkg,
    fw,
    hasJournald,
    journalReadable,
    arch,
    discoveredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_facts';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedFactsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('os_id')) {
      context.handle(
        _osIdMeta,
        osId.isAcceptableOrUnknown(data['os_id']!, _osIdMeta),
      );
    } else if (isInserting) {
      context.missing(_osIdMeta);
    }
    if (data.containsKey('os_version_id')) {
      context.handle(
        _osVersionIdMeta,
        osVersionId.isAcceptableOrUnknown(
          data['os_version_id']!,
          _osVersionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_osVersionIdMeta);
    }
    if (data.containsKey('pretty_name')) {
      context.handle(
        _prettyNameMeta,
        prettyName.isAcceptableOrUnknown(data['pretty_name']!, _prettyNameMeta),
      );
    }
    if (data.containsKey('init_system')) {
      context.handle(
        _initSystemMeta,
        initSystem.isAcceptableOrUnknown(data['init_system']!, _initSystemMeta),
      );
    } else if (isInserting) {
      context.missing(_initSystemMeta);
    }
    if (data.containsKey('systemd_version')) {
      context.handle(
        _systemdVersionMeta,
        systemdVersion.isAcceptableOrUnknown(
          data['systemd_version']!,
          _systemdVersionMeta,
        ),
      );
    }
    if (data.containsKey('pkg')) {
      context.handle(
        _pkgMeta,
        pkg.isAcceptableOrUnknown(data['pkg']!, _pkgMeta),
      );
    } else if (isInserting) {
      context.missing(_pkgMeta);
    }
    if (data.containsKey('fw')) {
      context.handle(_fwMeta, fw.isAcceptableOrUnknown(data['fw']!, _fwMeta));
    } else if (isInserting) {
      context.missing(_fwMeta);
    }
    if (data.containsKey('has_journald')) {
      context.handle(
        _hasJournaldMeta,
        hasJournald.isAcceptableOrUnknown(
          data['has_journald']!,
          _hasJournaldMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hasJournaldMeta);
    }
    if (data.containsKey('journal_readable')) {
      context.handle(
        _journalReadableMeta,
        journalReadable.isAcceptableOrUnknown(
          data['journal_readable']!,
          _journalReadableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_journalReadableMeta);
    }
    if (data.containsKey('arch')) {
      context.handle(
        _archMeta,
        arch.isAcceptableOrUnknown(data['arch']!, _archMeta),
      );
    } else if (isInserting) {
      context.missing(_archMeta);
    }
    if (data.containsKey('discovered_at')) {
      context.handle(
        _discoveredAtMeta,
        discoveredAt.isAcceptableOrUnknown(
          data['discovered_at']!,
          _discoveredAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_discoveredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hostId};
  @override
  CachedFactsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedFactsRow(
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      osId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}os_id'],
      )!,
      osVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}os_version_id'],
      )!,
      prettyName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pretty_name'],
      ),
      initSystem: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}init_system'],
      )!,
      systemdVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}systemd_version'],
      ),
      pkg: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pkg'],
      )!,
      fw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fw'],
      )!,
      hasJournald: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_journald'],
      )!,
      journalReadable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}journal_readable'],
      )!,
      arch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}arch'],
      )!,
      discoveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}discovered_at'],
      )!,
    );
  }

  @override
  $CachedFactsTable createAlias(String alias) {
    return $CachedFactsTable(attachedDatabase, alias);
  }
}

class CachedFactsRow extends DataClass implements Insertable<CachedFactsRow> {
  final String hostId;
  final String osId;
  final String osVersionId;
  final String? prettyName;
  final String initSystem;
  final int? systemdVersion;
  final String pkg;
  final String fw;
  final bool hasJournald;
  final bool journalReadable;
  final String arch;
  final DateTime discoveredAt;
  const CachedFactsRow({
    required this.hostId,
    required this.osId,
    required this.osVersionId,
    this.prettyName,
    required this.initSystem,
    this.systemdVersion,
    required this.pkg,
    required this.fw,
    required this.hasJournald,
    required this.journalReadable,
    required this.arch,
    required this.discoveredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['host_id'] = Variable<String>(hostId);
    map['os_id'] = Variable<String>(osId);
    map['os_version_id'] = Variable<String>(osVersionId);
    if (!nullToAbsent || prettyName != null) {
      map['pretty_name'] = Variable<String>(prettyName);
    }
    map['init_system'] = Variable<String>(initSystem);
    if (!nullToAbsent || systemdVersion != null) {
      map['systemd_version'] = Variable<int>(systemdVersion);
    }
    map['pkg'] = Variable<String>(pkg);
    map['fw'] = Variable<String>(fw);
    map['has_journald'] = Variable<bool>(hasJournald);
    map['journal_readable'] = Variable<bool>(journalReadable);
    map['arch'] = Variable<String>(arch);
    map['discovered_at'] = Variable<DateTime>(discoveredAt);
    return map;
  }

  CachedFactsCompanion toCompanion(bool nullToAbsent) {
    return CachedFactsCompanion(
      hostId: Value(hostId),
      osId: Value(osId),
      osVersionId: Value(osVersionId),
      prettyName: prettyName == null && nullToAbsent
          ? const Value.absent()
          : Value(prettyName),
      initSystem: Value(initSystem),
      systemdVersion: systemdVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(systemdVersion),
      pkg: Value(pkg),
      fw: Value(fw),
      hasJournald: Value(hasJournald),
      journalReadable: Value(journalReadable),
      arch: Value(arch),
      discoveredAt: Value(discoveredAt),
    );
  }

  factory CachedFactsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedFactsRow(
      hostId: serializer.fromJson<String>(json['hostId']),
      osId: serializer.fromJson<String>(json['osId']),
      osVersionId: serializer.fromJson<String>(json['osVersionId']),
      prettyName: serializer.fromJson<String?>(json['prettyName']),
      initSystem: serializer.fromJson<String>(json['initSystem']),
      systemdVersion: serializer.fromJson<int?>(json['systemdVersion']),
      pkg: serializer.fromJson<String>(json['pkg']),
      fw: serializer.fromJson<String>(json['fw']),
      hasJournald: serializer.fromJson<bool>(json['hasJournald']),
      journalReadable: serializer.fromJson<bool>(json['journalReadable']),
      arch: serializer.fromJson<String>(json['arch']),
      discoveredAt: serializer.fromJson<DateTime>(json['discoveredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hostId': serializer.toJson<String>(hostId),
      'osId': serializer.toJson<String>(osId),
      'osVersionId': serializer.toJson<String>(osVersionId),
      'prettyName': serializer.toJson<String?>(prettyName),
      'initSystem': serializer.toJson<String>(initSystem),
      'systemdVersion': serializer.toJson<int?>(systemdVersion),
      'pkg': serializer.toJson<String>(pkg),
      'fw': serializer.toJson<String>(fw),
      'hasJournald': serializer.toJson<bool>(hasJournald),
      'journalReadable': serializer.toJson<bool>(journalReadable),
      'arch': serializer.toJson<String>(arch),
      'discoveredAt': serializer.toJson<DateTime>(discoveredAt),
    };
  }

  CachedFactsRow copyWith({
    String? hostId,
    String? osId,
    String? osVersionId,
    Value<String?> prettyName = const Value.absent(),
    String? initSystem,
    Value<int?> systemdVersion = const Value.absent(),
    String? pkg,
    String? fw,
    bool? hasJournald,
    bool? journalReadable,
    String? arch,
    DateTime? discoveredAt,
  }) => CachedFactsRow(
    hostId: hostId ?? this.hostId,
    osId: osId ?? this.osId,
    osVersionId: osVersionId ?? this.osVersionId,
    prettyName: prettyName.present ? prettyName.value : this.prettyName,
    initSystem: initSystem ?? this.initSystem,
    systemdVersion: systemdVersion.present
        ? systemdVersion.value
        : this.systemdVersion,
    pkg: pkg ?? this.pkg,
    fw: fw ?? this.fw,
    hasJournald: hasJournald ?? this.hasJournald,
    journalReadable: journalReadable ?? this.journalReadable,
    arch: arch ?? this.arch,
    discoveredAt: discoveredAt ?? this.discoveredAt,
  );
  CachedFactsRow copyWithCompanion(CachedFactsCompanion data) {
    return CachedFactsRow(
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      osId: data.osId.present ? data.osId.value : this.osId,
      osVersionId: data.osVersionId.present
          ? data.osVersionId.value
          : this.osVersionId,
      prettyName: data.prettyName.present
          ? data.prettyName.value
          : this.prettyName,
      initSystem: data.initSystem.present
          ? data.initSystem.value
          : this.initSystem,
      systemdVersion: data.systemdVersion.present
          ? data.systemdVersion.value
          : this.systemdVersion,
      pkg: data.pkg.present ? data.pkg.value : this.pkg,
      fw: data.fw.present ? data.fw.value : this.fw,
      hasJournald: data.hasJournald.present
          ? data.hasJournald.value
          : this.hasJournald,
      journalReadable: data.journalReadable.present
          ? data.journalReadable.value
          : this.journalReadable,
      arch: data.arch.present ? data.arch.value : this.arch,
      discoveredAt: data.discoveredAt.present
          ? data.discoveredAt.value
          : this.discoveredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedFactsRow(')
          ..write('hostId: $hostId, ')
          ..write('osId: $osId, ')
          ..write('osVersionId: $osVersionId, ')
          ..write('prettyName: $prettyName, ')
          ..write('initSystem: $initSystem, ')
          ..write('systemdVersion: $systemdVersion, ')
          ..write('pkg: $pkg, ')
          ..write('fw: $fw, ')
          ..write('hasJournald: $hasJournald, ')
          ..write('journalReadable: $journalReadable, ')
          ..write('arch: $arch, ')
          ..write('discoveredAt: $discoveredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    hostId,
    osId,
    osVersionId,
    prettyName,
    initSystem,
    systemdVersion,
    pkg,
    fw,
    hasJournald,
    journalReadable,
    arch,
    discoveredAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedFactsRow &&
          other.hostId == this.hostId &&
          other.osId == this.osId &&
          other.osVersionId == this.osVersionId &&
          other.prettyName == this.prettyName &&
          other.initSystem == this.initSystem &&
          other.systemdVersion == this.systemdVersion &&
          other.pkg == this.pkg &&
          other.fw == this.fw &&
          other.hasJournald == this.hasJournald &&
          other.journalReadable == this.journalReadable &&
          other.arch == this.arch &&
          other.discoveredAt == this.discoveredAt);
}

class CachedFactsCompanion extends UpdateCompanion<CachedFactsRow> {
  final Value<String> hostId;
  final Value<String> osId;
  final Value<String> osVersionId;
  final Value<String?> prettyName;
  final Value<String> initSystem;
  final Value<int?> systemdVersion;
  final Value<String> pkg;
  final Value<String> fw;
  final Value<bool> hasJournald;
  final Value<bool> journalReadable;
  final Value<String> arch;
  final Value<DateTime> discoveredAt;
  final Value<int> rowid;
  const CachedFactsCompanion({
    this.hostId = const Value.absent(),
    this.osId = const Value.absent(),
    this.osVersionId = const Value.absent(),
    this.prettyName = const Value.absent(),
    this.initSystem = const Value.absent(),
    this.systemdVersion = const Value.absent(),
    this.pkg = const Value.absent(),
    this.fw = const Value.absent(),
    this.hasJournald = const Value.absent(),
    this.journalReadable = const Value.absent(),
    this.arch = const Value.absent(),
    this.discoveredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedFactsCompanion.insert({
    required String hostId,
    required String osId,
    required String osVersionId,
    this.prettyName = const Value.absent(),
    required String initSystem,
    this.systemdVersion = const Value.absent(),
    required String pkg,
    required String fw,
    required bool hasJournald,
    required bool journalReadable,
    required String arch,
    required DateTime discoveredAt,
    this.rowid = const Value.absent(),
  }) : hostId = Value(hostId),
       osId = Value(osId),
       osVersionId = Value(osVersionId),
       initSystem = Value(initSystem),
       pkg = Value(pkg),
       fw = Value(fw),
       hasJournald = Value(hasJournald),
       journalReadable = Value(journalReadable),
       arch = Value(arch),
       discoveredAt = Value(discoveredAt);
  static Insertable<CachedFactsRow> custom({
    Expression<String>? hostId,
    Expression<String>? osId,
    Expression<String>? osVersionId,
    Expression<String>? prettyName,
    Expression<String>? initSystem,
    Expression<int>? systemdVersion,
    Expression<String>? pkg,
    Expression<String>? fw,
    Expression<bool>? hasJournald,
    Expression<bool>? journalReadable,
    Expression<String>? arch,
    Expression<DateTime>? discoveredAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (hostId != null) 'host_id': hostId,
      if (osId != null) 'os_id': osId,
      if (osVersionId != null) 'os_version_id': osVersionId,
      if (prettyName != null) 'pretty_name': prettyName,
      if (initSystem != null) 'init_system': initSystem,
      if (systemdVersion != null) 'systemd_version': systemdVersion,
      if (pkg != null) 'pkg': pkg,
      if (fw != null) 'fw': fw,
      if (hasJournald != null) 'has_journald': hasJournald,
      if (journalReadable != null) 'journal_readable': journalReadable,
      if (arch != null) 'arch': arch,
      if (discoveredAt != null) 'discovered_at': discoveredAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedFactsCompanion copyWith({
    Value<String>? hostId,
    Value<String>? osId,
    Value<String>? osVersionId,
    Value<String?>? prettyName,
    Value<String>? initSystem,
    Value<int?>? systemdVersion,
    Value<String>? pkg,
    Value<String>? fw,
    Value<bool>? hasJournald,
    Value<bool>? journalReadable,
    Value<String>? arch,
    Value<DateTime>? discoveredAt,
    Value<int>? rowid,
  }) {
    return CachedFactsCompanion(
      hostId: hostId ?? this.hostId,
      osId: osId ?? this.osId,
      osVersionId: osVersionId ?? this.osVersionId,
      prettyName: prettyName ?? this.prettyName,
      initSystem: initSystem ?? this.initSystem,
      systemdVersion: systemdVersion ?? this.systemdVersion,
      pkg: pkg ?? this.pkg,
      fw: fw ?? this.fw,
      hasJournald: hasJournald ?? this.hasJournald,
      journalReadable: journalReadable ?? this.journalReadable,
      arch: arch ?? this.arch,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (osId.present) {
      map['os_id'] = Variable<String>(osId.value);
    }
    if (osVersionId.present) {
      map['os_version_id'] = Variable<String>(osVersionId.value);
    }
    if (prettyName.present) {
      map['pretty_name'] = Variable<String>(prettyName.value);
    }
    if (initSystem.present) {
      map['init_system'] = Variable<String>(initSystem.value);
    }
    if (systemdVersion.present) {
      map['systemd_version'] = Variable<int>(systemdVersion.value);
    }
    if (pkg.present) {
      map['pkg'] = Variable<String>(pkg.value);
    }
    if (fw.present) {
      map['fw'] = Variable<String>(fw.value);
    }
    if (hasJournald.present) {
      map['has_journald'] = Variable<bool>(hasJournald.value);
    }
    if (journalReadable.present) {
      map['journal_readable'] = Variable<bool>(journalReadable.value);
    }
    if (arch.present) {
      map['arch'] = Variable<String>(arch.value);
    }
    if (discoveredAt.present) {
      map['discovered_at'] = Variable<DateTime>(discoveredAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedFactsCompanion(')
          ..write('hostId: $hostId, ')
          ..write('osId: $osId, ')
          ..write('osVersionId: $osVersionId, ')
          ..write('prettyName: $prettyName, ')
          ..write('initSystem: $initSystem, ')
          ..write('systemdVersion: $systemdVersion, ')
          ..write('pkg: $pkg, ')
          ..write('fw: $fw, ')
          ..write('hasJournald: $hasJournald, ')
          ..write('journalReadable: $journalReadable, ')
          ..write('arch: $arch, ')
          ..write('discoveredAt: $discoveredAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecentsTable extends Recents with TableInfo<$RecentsTable, RecentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _viewedAtMeta = const VerificationMeta(
    'viewedAt',
  );
  @override
  late final GeneratedColumn<DateTime> viewedAt = GeneratedColumn<DateTime>(
    'viewed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, kind, hostId, label, viewedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recents';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('viewed_at')) {
      context.handle(
        _viewedAtMeta,
        viewedAt.isAcceptableOrUnknown(data['viewed_at']!, _viewedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_viewedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      viewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}viewed_at'],
      )!,
    );
  }

  @override
  $RecentsTable createAlias(String alias) {
    return $RecentsTable(attachedDatabase, alias);
  }
}

class RecentRow extends DataClass implements Insertable<RecentRow> {
  final int id;
  final String kind;
  final String hostId;
  final String label;
  final DateTime viewedAt;
  const RecentRow({
    required this.id,
    required this.kind,
    required this.hostId,
    required this.label,
    required this.viewedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['host_id'] = Variable<String>(hostId);
    map['label'] = Variable<String>(label);
    map['viewed_at'] = Variable<DateTime>(viewedAt);
    return map;
  }

  RecentsCompanion toCompanion(bool nullToAbsent) {
    return RecentsCompanion(
      id: Value(id),
      kind: Value(kind),
      hostId: Value(hostId),
      label: Value(label),
      viewedAt: Value(viewedAt),
    );
  }

  factory RecentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentRow(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      hostId: serializer.fromJson<String>(json['hostId']),
      label: serializer.fromJson<String>(json['label']),
      viewedAt: serializer.fromJson<DateTime>(json['viewedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'hostId': serializer.toJson<String>(hostId),
      'label': serializer.toJson<String>(label),
      'viewedAt': serializer.toJson<DateTime>(viewedAt),
    };
  }

  RecentRow copyWith({
    int? id,
    String? kind,
    String? hostId,
    String? label,
    DateTime? viewedAt,
  }) => RecentRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    hostId: hostId ?? this.hostId,
    label: label ?? this.label,
    viewedAt: viewedAt ?? this.viewedAt,
  );
  RecentRow copyWithCompanion(RecentsCompanion data) {
    return RecentRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      label: data.label.present ? data.label.value : this.label,
      viewedAt: data.viewedAt.present ? data.viewedAt.value : this.viewedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('hostId: $hostId, ')
          ..write('label: $label, ')
          ..write('viewedAt: $viewedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, kind, hostId, label, viewedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.hostId == this.hostId &&
          other.label == this.label &&
          other.viewedAt == this.viewedAt);
}

class RecentsCompanion extends UpdateCompanion<RecentRow> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String> hostId;
  final Value<String> label;
  final Value<DateTime> viewedAt;
  const RecentsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.hostId = const Value.absent(),
    this.label = const Value.absent(),
    this.viewedAt = const Value.absent(),
  });
  RecentsCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required String hostId,
    required String label,
    required DateTime viewedAt,
  }) : kind = Value(kind),
       hostId = Value(hostId),
       label = Value(label),
       viewedAt = Value(viewedAt);
  static Insertable<RecentRow> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? hostId,
    Expression<String>? label,
    Expression<DateTime>? viewedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (hostId != null) 'host_id': hostId,
      if (label != null) 'label': label,
      if (viewedAt != null) 'viewed_at': viewedAt,
    });
  }

  RecentsCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String>? hostId,
    Value<String>? label,
    Value<DateTime>? viewedAt,
  }) {
    return RecentsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      hostId: hostId ?? this.hostId,
      label: label ?? this.label,
      viewedAt: viewedAt ?? this.viewedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (viewedAt.present) {
      map['viewed_at'] = Variable<DateTime>(viewedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('hostId: $hostId, ')
          ..write('label: $label, ')
          ..write('viewedAt: $viewedAt')
          ..write(')'))
        .toString();
  }
}

class $PinsTable extends Pins with TableInfo<$PinsTable, PinRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PinsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _routeMeta = const VerificationMeta('route');
  @override
  late final GeneratedColumn<String> route = GeneratedColumn<String>(
    'route',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hostId,
    kind,
    label,
    route,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pins';
  @override
  VerificationContext validateIntegrity(
    Insertable<PinRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('route')) {
      context.handle(
        _routeMeta,
        route.isAcceptableOrUnknown(data['route']!, _routeMeta),
      );
    } else if (isInserting) {
      context.missing(_routeMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PinRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PinRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      route: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $PinsTable createAlias(String alias) {
    return $PinsTable(attachedDatabase, alias);
  }
}

class PinRow extends DataClass implements Insertable<PinRow> {
  final int id;
  final String hostId;
  final String kind;
  final String label;
  final String route;
  final int sortOrder;
  const PinRow({
    required this.id,
    required this.hostId,
    required this.kind,
    required this.label,
    required this.route,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['host_id'] = Variable<String>(hostId);
    map['kind'] = Variable<String>(kind);
    map['label'] = Variable<String>(label);
    map['route'] = Variable<String>(route);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  PinsCompanion toCompanion(bool nullToAbsent) {
    return PinsCompanion(
      id: Value(id),
      hostId: Value(hostId),
      kind: Value(kind),
      label: Value(label),
      route: Value(route),
      sortOrder: Value(sortOrder),
    );
  }

  factory PinRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PinRow(
      id: serializer.fromJson<int>(json['id']),
      hostId: serializer.fromJson<String>(json['hostId']),
      kind: serializer.fromJson<String>(json['kind']),
      label: serializer.fromJson<String>(json['label']),
      route: serializer.fromJson<String>(json['route']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'hostId': serializer.toJson<String>(hostId),
      'kind': serializer.toJson<String>(kind),
      'label': serializer.toJson<String>(label),
      'route': serializer.toJson<String>(route),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  PinRow copyWith({
    int? id,
    String? hostId,
    String? kind,
    String? label,
    String? route,
    int? sortOrder,
  }) => PinRow(
    id: id ?? this.id,
    hostId: hostId ?? this.hostId,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    route: route ?? this.route,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  PinRow copyWithCompanion(PinsCompanion data) {
    return PinRow(
      id: data.id.present ? data.id.value : this.id,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      kind: data.kind.present ? data.kind.value : this.kind,
      label: data.label.present ? data.label.value : this.label,
      route: data.route.present ? data.route.value : this.route,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PinRow(')
          ..write('id: $id, ')
          ..write('hostId: $hostId, ')
          ..write('kind: $kind, ')
          ..write('label: $label, ')
          ..write('route: $route, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, hostId, kind, label, route, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PinRow &&
          other.id == this.id &&
          other.hostId == this.hostId &&
          other.kind == this.kind &&
          other.label == this.label &&
          other.route == this.route &&
          other.sortOrder == this.sortOrder);
}

class PinsCompanion extends UpdateCompanion<PinRow> {
  final Value<int> id;
  final Value<String> hostId;
  final Value<String> kind;
  final Value<String> label;
  final Value<String> route;
  final Value<int> sortOrder;
  const PinsCompanion({
    this.id = const Value.absent(),
    this.hostId = const Value.absent(),
    this.kind = const Value.absent(),
    this.label = const Value.absent(),
    this.route = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  PinsCompanion.insert({
    this.id = const Value.absent(),
    required String hostId,
    required String kind,
    required String label,
    required String route,
    required int sortOrder,
  }) : hostId = Value(hostId),
       kind = Value(kind),
       label = Value(label),
       route = Value(route),
       sortOrder = Value(sortOrder);
  static Insertable<PinRow> custom({
    Expression<int>? id,
    Expression<String>? hostId,
    Expression<String>? kind,
    Expression<String>? label,
    Expression<String>? route,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hostId != null) 'host_id': hostId,
      if (kind != null) 'kind': kind,
      if (label != null) 'label': label,
      if (route != null) 'route': route,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  PinsCompanion copyWith({
    Value<int>? id,
    Value<String>? hostId,
    Value<String>? kind,
    Value<String>? label,
    Value<String>? route,
    Value<int>? sortOrder,
  }) {
    return PinsCompanion(
      id: id ?? this.id,
      hostId: hostId ?? this.hostId,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      route: route ?? this.route,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (route.present) {
      map['route'] = Variable<String>(route.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PinsCompanion(')
          ..write('id: $id, ')
          ..write('hostId: $hostId, ')
          ..write('kind: $kind, ')
          ..write('label: $label, ')
          ..write('route: $route, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }
}

class $AuditRecordsTable extends AuditRecords
    with TableInfo<$AuditRecordsTable, AuditRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampUtcMeta = const VerificationMeta(
    'timestampUtc',
  );
  @override
  late final GeneratedColumn<DateTime> timestampUtc = GeneratedColumn<DateTime>(
    'timestamp_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostAliasMeta = const VerificationMeta(
    'hostAlias',
  );
  @override
  late final GeneratedColumn<String> hostAlias = GeneratedColumn<String>(
    'host_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteUserMeta = const VerificationMeta(
    'remoteUser',
  );
  @override
  late final GeneratedColumn<String> remoteUser = GeneratedColumn<String>(
    'remote_user',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _commandMeta = const VerificationMeta(
    'command',
  );
  @override
  late final GeneratedColumn<String> command = GeneratedColumn<String>(
    'command',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _riskMeta = const VerificationMeta('risk');
  @override
  late final GeneratedColumn<String> risk = GeneratedColumn<String>(
    'risk',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usedSudoMeta = const VerificationMeta(
    'usedSudo',
  );
  @override
  late final GeneratedColumn<bool> usedSudo = GeneratedColumn<bool>(
    'used_sudo',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("used_sudo" IN (0, 1))',
    ),
  );
  static const VerificationMeta _exitCodeMeta = const VerificationMeta(
    'exitCode',
  );
  @override
  late final GeneratedColumn<int> exitCode = GeneratedColumn<int>(
    'exit_code',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorSummaryMeta = const VerificationMeta(
    'errorSummary',
  );
  @override
  late final GeneratedColumn<String> errorSummary = GeneratedColumn<String>(
    'error_summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  @override
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    timestampUtc,
    hostId,
    hostAlias,
    remoteUser,
    title,
    command,
    risk,
    usedSudo,
    exitCode,
    durationMs,
    errorSummary,
    appVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('timestamp_utc')) {
      context.handle(
        _timestampUtcMeta,
        timestampUtc.isAcceptableOrUnknown(
          data['timestamp_utc']!,
          _timestampUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timestampUtcMeta);
    }
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('host_alias')) {
      context.handle(
        _hostAliasMeta,
        hostAlias.isAcceptableOrUnknown(data['host_alias']!, _hostAliasMeta),
      );
    } else if (isInserting) {
      context.missing(_hostAliasMeta);
    }
    if (data.containsKey('remote_user')) {
      context.handle(
        _remoteUserMeta,
        remoteUser.isAcceptableOrUnknown(data['remote_user']!, _remoteUserMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteUserMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('command')) {
      context.handle(
        _commandMeta,
        command.isAcceptableOrUnknown(data['command']!, _commandMeta),
      );
    } else if (isInserting) {
      context.missing(_commandMeta);
    }
    if (data.containsKey('risk')) {
      context.handle(
        _riskMeta,
        risk.isAcceptableOrUnknown(data['risk']!, _riskMeta),
      );
    } else if (isInserting) {
      context.missing(_riskMeta);
    }
    if (data.containsKey('used_sudo')) {
      context.handle(
        _usedSudoMeta,
        usedSudo.isAcceptableOrUnknown(data['used_sudo']!, _usedSudoMeta),
      );
    } else if (isInserting) {
      context.missing(_usedSudoMeta);
    }
    if (data.containsKey('exit_code')) {
      context.handle(
        _exitCodeMeta,
        exitCode.isAcceptableOrUnknown(data['exit_code']!, _exitCodeMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('error_summary')) {
      context.handle(
        _errorSummaryMeta,
        errorSummary.isAcceptableOrUnknown(
          data['error_summary']!,
          _errorSummaryMeta,
        ),
      );
    }
    if (data.containsKey('app_version')) {
      context.handle(
        _appVersionMeta,
        appVersion.isAcceptableOrUnknown(data['app_version']!, _appVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_appVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      timestampUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp_utc'],
      )!,
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      hostAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_alias'],
      )!,
      remoteUser: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_user'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      command: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command'],
      )!,
      risk: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}risk'],
      )!,
      usedSudo: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}used_sudo'],
      )!,
      exitCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}exit_code'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      errorSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_summary'],
      ),
      appVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_version'],
      )!,
    );
  }

  @override
  $AuditRecordsTable createAlias(String alias) {
    return $AuditRecordsTable(attachedDatabase, alias);
  }
}

class AuditRow extends DataClass implements Insertable<AuditRow> {
  final String id;
  final DateTime timestampUtc;
  final String hostId;
  final String hostAlias;
  final String remoteUser;
  final String title;
  final String command;
  final String risk;
  final bool usedSudo;
  final int? exitCode;
  final int durationMs;
  final String? errorSummary;
  final String appVersion;
  const AuditRow({
    required this.id,
    required this.timestampUtc,
    required this.hostId,
    required this.hostAlias,
    required this.remoteUser,
    required this.title,
    required this.command,
    required this.risk,
    required this.usedSudo,
    this.exitCode,
    required this.durationMs,
    this.errorSummary,
    required this.appVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['timestamp_utc'] = Variable<DateTime>(timestampUtc);
    map['host_id'] = Variable<String>(hostId);
    map['host_alias'] = Variable<String>(hostAlias);
    map['remote_user'] = Variable<String>(remoteUser);
    map['title'] = Variable<String>(title);
    map['command'] = Variable<String>(command);
    map['risk'] = Variable<String>(risk);
    map['used_sudo'] = Variable<bool>(usedSudo);
    if (!nullToAbsent || exitCode != null) {
      map['exit_code'] = Variable<int>(exitCode);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    if (!nullToAbsent || errorSummary != null) {
      map['error_summary'] = Variable<String>(errorSummary);
    }
    map['app_version'] = Variable<String>(appVersion);
    return map;
  }

  AuditRecordsCompanion toCompanion(bool nullToAbsent) {
    return AuditRecordsCompanion(
      id: Value(id),
      timestampUtc: Value(timestampUtc),
      hostId: Value(hostId),
      hostAlias: Value(hostAlias),
      remoteUser: Value(remoteUser),
      title: Value(title),
      command: Value(command),
      risk: Value(risk),
      usedSudo: Value(usedSudo),
      exitCode: exitCode == null && nullToAbsent
          ? const Value.absent()
          : Value(exitCode),
      durationMs: Value(durationMs),
      errorSummary: errorSummary == null && nullToAbsent
          ? const Value.absent()
          : Value(errorSummary),
      appVersion: Value(appVersion),
    );
  }

  factory AuditRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditRow(
      id: serializer.fromJson<String>(json['id']),
      timestampUtc: serializer.fromJson<DateTime>(json['timestampUtc']),
      hostId: serializer.fromJson<String>(json['hostId']),
      hostAlias: serializer.fromJson<String>(json['hostAlias']),
      remoteUser: serializer.fromJson<String>(json['remoteUser']),
      title: serializer.fromJson<String>(json['title']),
      command: serializer.fromJson<String>(json['command']),
      risk: serializer.fromJson<String>(json['risk']),
      usedSudo: serializer.fromJson<bool>(json['usedSudo']),
      exitCode: serializer.fromJson<int?>(json['exitCode']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      errorSummary: serializer.fromJson<String?>(json['errorSummary']),
      appVersion: serializer.fromJson<String>(json['appVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'timestampUtc': serializer.toJson<DateTime>(timestampUtc),
      'hostId': serializer.toJson<String>(hostId),
      'hostAlias': serializer.toJson<String>(hostAlias),
      'remoteUser': serializer.toJson<String>(remoteUser),
      'title': serializer.toJson<String>(title),
      'command': serializer.toJson<String>(command),
      'risk': serializer.toJson<String>(risk),
      'usedSudo': serializer.toJson<bool>(usedSudo),
      'exitCode': serializer.toJson<int?>(exitCode),
      'durationMs': serializer.toJson<int>(durationMs),
      'errorSummary': serializer.toJson<String?>(errorSummary),
      'appVersion': serializer.toJson<String>(appVersion),
    };
  }

  AuditRow copyWith({
    String? id,
    DateTime? timestampUtc,
    String? hostId,
    String? hostAlias,
    String? remoteUser,
    String? title,
    String? command,
    String? risk,
    bool? usedSudo,
    Value<int?> exitCode = const Value.absent(),
    int? durationMs,
    Value<String?> errorSummary = const Value.absent(),
    String? appVersion,
  }) => AuditRow(
    id: id ?? this.id,
    timestampUtc: timestampUtc ?? this.timestampUtc,
    hostId: hostId ?? this.hostId,
    hostAlias: hostAlias ?? this.hostAlias,
    remoteUser: remoteUser ?? this.remoteUser,
    title: title ?? this.title,
    command: command ?? this.command,
    risk: risk ?? this.risk,
    usedSudo: usedSudo ?? this.usedSudo,
    exitCode: exitCode.present ? exitCode.value : this.exitCode,
    durationMs: durationMs ?? this.durationMs,
    errorSummary: errorSummary.present ? errorSummary.value : this.errorSummary,
    appVersion: appVersion ?? this.appVersion,
  );
  AuditRow copyWithCompanion(AuditRecordsCompanion data) {
    return AuditRow(
      id: data.id.present ? data.id.value : this.id,
      timestampUtc: data.timestampUtc.present
          ? data.timestampUtc.value
          : this.timestampUtc,
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      hostAlias: data.hostAlias.present ? data.hostAlias.value : this.hostAlias,
      remoteUser: data.remoteUser.present
          ? data.remoteUser.value
          : this.remoteUser,
      title: data.title.present ? data.title.value : this.title,
      command: data.command.present ? data.command.value : this.command,
      risk: data.risk.present ? data.risk.value : this.risk,
      usedSudo: data.usedSudo.present ? data.usedSudo.value : this.usedSudo,
      exitCode: data.exitCode.present ? data.exitCode.value : this.exitCode,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      errorSummary: data.errorSummary.present
          ? data.errorSummary.value
          : this.errorSummary,
      appVersion: data.appVersion.present
          ? data.appVersion.value
          : this.appVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditRow(')
          ..write('id: $id, ')
          ..write('timestampUtc: $timestampUtc, ')
          ..write('hostId: $hostId, ')
          ..write('hostAlias: $hostAlias, ')
          ..write('remoteUser: $remoteUser, ')
          ..write('title: $title, ')
          ..write('command: $command, ')
          ..write('risk: $risk, ')
          ..write('usedSudo: $usedSudo, ')
          ..write('exitCode: $exitCode, ')
          ..write('durationMs: $durationMs, ')
          ..write('errorSummary: $errorSummary, ')
          ..write('appVersion: $appVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    timestampUtc,
    hostId,
    hostAlias,
    remoteUser,
    title,
    command,
    risk,
    usedSudo,
    exitCode,
    durationMs,
    errorSummary,
    appVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditRow &&
          other.id == this.id &&
          other.timestampUtc == this.timestampUtc &&
          other.hostId == this.hostId &&
          other.hostAlias == this.hostAlias &&
          other.remoteUser == this.remoteUser &&
          other.title == this.title &&
          other.command == this.command &&
          other.risk == this.risk &&
          other.usedSudo == this.usedSudo &&
          other.exitCode == this.exitCode &&
          other.durationMs == this.durationMs &&
          other.errorSummary == this.errorSummary &&
          other.appVersion == this.appVersion);
}

class AuditRecordsCompanion extends UpdateCompanion<AuditRow> {
  final Value<String> id;
  final Value<DateTime> timestampUtc;
  final Value<String> hostId;
  final Value<String> hostAlias;
  final Value<String> remoteUser;
  final Value<String> title;
  final Value<String> command;
  final Value<String> risk;
  final Value<bool> usedSudo;
  final Value<int?> exitCode;
  final Value<int> durationMs;
  final Value<String?> errorSummary;
  final Value<String> appVersion;
  final Value<int> rowid;
  const AuditRecordsCompanion({
    this.id = const Value.absent(),
    this.timestampUtc = const Value.absent(),
    this.hostId = const Value.absent(),
    this.hostAlias = const Value.absent(),
    this.remoteUser = const Value.absent(),
    this.title = const Value.absent(),
    this.command = const Value.absent(),
    this.risk = const Value.absent(),
    this.usedSudo = const Value.absent(),
    this.exitCode = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.errorSummary = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AuditRecordsCompanion.insert({
    required String id,
    required DateTime timestampUtc,
    required String hostId,
    required String hostAlias,
    required String remoteUser,
    this.title = const Value.absent(),
    required String command,
    required String risk,
    required bool usedSudo,
    this.exitCode = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.errorSummary = const Value.absent(),
    required String appVersion,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       timestampUtc = Value(timestampUtc),
       hostId = Value(hostId),
       hostAlias = Value(hostAlias),
       remoteUser = Value(remoteUser),
       command = Value(command),
       risk = Value(risk),
       usedSudo = Value(usedSudo),
       appVersion = Value(appVersion);
  static Insertable<AuditRow> custom({
    Expression<String>? id,
    Expression<DateTime>? timestampUtc,
    Expression<String>? hostId,
    Expression<String>? hostAlias,
    Expression<String>? remoteUser,
    Expression<String>? title,
    Expression<String>? command,
    Expression<String>? risk,
    Expression<bool>? usedSudo,
    Expression<int>? exitCode,
    Expression<int>? durationMs,
    Expression<String>? errorSummary,
    Expression<String>? appVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (timestampUtc != null) 'timestamp_utc': timestampUtc,
      if (hostId != null) 'host_id': hostId,
      if (hostAlias != null) 'host_alias': hostAlias,
      if (remoteUser != null) 'remote_user': remoteUser,
      if (title != null) 'title': title,
      if (command != null) 'command': command,
      if (risk != null) 'risk': risk,
      if (usedSudo != null) 'used_sudo': usedSudo,
      if (exitCode != null) 'exit_code': exitCode,
      if (durationMs != null) 'duration_ms': durationMs,
      if (errorSummary != null) 'error_summary': errorSummary,
      if (appVersion != null) 'app_version': appVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AuditRecordsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? timestampUtc,
    Value<String>? hostId,
    Value<String>? hostAlias,
    Value<String>? remoteUser,
    Value<String>? title,
    Value<String>? command,
    Value<String>? risk,
    Value<bool>? usedSudo,
    Value<int?>? exitCode,
    Value<int>? durationMs,
    Value<String?>? errorSummary,
    Value<String>? appVersion,
    Value<int>? rowid,
  }) {
    return AuditRecordsCompanion(
      id: id ?? this.id,
      timestampUtc: timestampUtc ?? this.timestampUtc,
      hostId: hostId ?? this.hostId,
      hostAlias: hostAlias ?? this.hostAlias,
      remoteUser: remoteUser ?? this.remoteUser,
      title: title ?? this.title,
      command: command ?? this.command,
      risk: risk ?? this.risk,
      usedSudo: usedSudo ?? this.usedSudo,
      exitCode: exitCode ?? this.exitCode,
      durationMs: durationMs ?? this.durationMs,
      errorSummary: errorSummary ?? this.errorSummary,
      appVersion: appVersion ?? this.appVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (timestampUtc.present) {
      map['timestamp_utc'] = Variable<DateTime>(timestampUtc.value);
    }
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (hostAlias.present) {
      map['host_alias'] = Variable<String>(hostAlias.value);
    }
    if (remoteUser.present) {
      map['remote_user'] = Variable<String>(remoteUser.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (command.present) {
      map['command'] = Variable<String>(command.value);
    }
    if (risk.present) {
      map['risk'] = Variable<String>(risk.value);
    }
    if (usedSudo.present) {
      map['used_sudo'] = Variable<bool>(usedSudo.value);
    }
    if (exitCode.present) {
      map['exit_code'] = Variable<int>(exitCode.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (errorSummary.present) {
      map['error_summary'] = Variable<String>(errorSummary.value);
    }
    if (appVersion.present) {
      map['app_version'] = Variable<String>(appVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditRecordsCompanion(')
          ..write('id: $id, ')
          ..write('timestampUtc: $timestampUtc, ')
          ..write('hostId: $hostId, ')
          ..write('hostAlias: $hostAlias, ')
          ..write('remoteUser: $remoteUser, ')
          ..write('title: $title, ')
          ..write('command: $command, ')
          ..write('risk: $risk, ')
          ..write('usedSudo: $usedSudo, ')
          ..write('exitCode: $exitCode, ')
          ..write('durationMs: $durationMs, ')
          ..write('errorSummary: $errorSummary, ')
          ..write('appVersion: $appVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastHostIdMeta = const VerificationMeta(
    'lastHostId',
  );
  @override
  late final GeneratedColumn<String> lastHostId = GeneratedColumn<String>(
    'last_host_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publicKeySpkiB64Meta = const VerificationMeta(
    'publicKeySpkiB64',
  );
  @override
  late final GeneratedColumn<String> publicKeySpkiB64 = GeneratedColumn<String>(
    'public_key_spki_b64',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _keyBackendMeta = const VerificationMeta(
    'keyBackend',
  );
  @override
  late final GeneratedColumn<String> keyBackend = GeneratedColumn<String>(
    'key_backend',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widgetEnabledMeta = const VerificationMeta(
    'widgetEnabled',
  );
  @override
  late final GeneratedColumn<bool> widgetEnabled = GeneratedColumn<bool>(
    'widget_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("widget_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _llmProviderMeta = const VerificationMeta(
    'llmProvider',
  );
  @override
  late final GeneratedColumn<String> llmProvider = GeneratedColumn<String>(
    'llm_provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _llmBaseUrlMeta = const VerificationMeta(
    'llmBaseUrl',
  );
  @override
  late final GeneratedColumn<String> llmBaseUrl = GeneratedColumn<String>(
    'llm_base_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _llmApiKeyMeta = const VerificationMeta(
    'llmApiKey',
  );
  @override
  late final GeneratedColumn<String> llmApiKey = GeneratedColumn<String>(
    'llm_api_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _llmModelMeta = const VerificationMeta(
    'llmModel',
  );
  @override
  late final GeneratedColumn<String> llmModel = GeneratedColumn<String>(
    'llm_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    lastHostId,
    publicKeySpkiB64,
    keyBackend,
    widgetEnabled,
    llmProvider,
    llmBaseUrl,
    llmApiKey,
    llmModel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('last_host_id')) {
      context.handle(
        _lastHostIdMeta,
        lastHostId.isAcceptableOrUnknown(
          data['last_host_id']!,
          _lastHostIdMeta,
        ),
      );
    }
    if (data.containsKey('public_key_spki_b64')) {
      context.handle(
        _publicKeySpkiB64Meta,
        publicKeySpkiB64.isAcceptableOrUnknown(
          data['public_key_spki_b64']!,
          _publicKeySpkiB64Meta,
        ),
      );
    }
    if (data.containsKey('key_backend')) {
      context.handle(
        _keyBackendMeta,
        keyBackend.isAcceptableOrUnknown(data['key_backend']!, _keyBackendMeta),
      );
    }
    if (data.containsKey('widget_enabled')) {
      context.handle(
        _widgetEnabledMeta,
        widgetEnabled.isAcceptableOrUnknown(
          data['widget_enabled']!,
          _widgetEnabledMeta,
        ),
      );
    }
    if (data.containsKey('llm_provider')) {
      context.handle(
        _llmProviderMeta,
        llmProvider.isAcceptableOrUnknown(
          data['llm_provider']!,
          _llmProviderMeta,
        ),
      );
    }
    if (data.containsKey('llm_base_url')) {
      context.handle(
        _llmBaseUrlMeta,
        llmBaseUrl.isAcceptableOrUnknown(
          data['llm_base_url']!,
          _llmBaseUrlMeta,
        ),
      );
    }
    if (data.containsKey('llm_api_key')) {
      context.handle(
        _llmApiKeyMeta,
        llmApiKey.isAcceptableOrUnknown(data['llm_api_key']!, _llmApiKeyMeta),
      );
    }
    if (data.containsKey('llm_model')) {
      context.handle(
        _llmModelMeta,
        llmModel.isAcceptableOrUnknown(data['llm_model']!, _llmModelMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      lastHostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_host_id'],
      ),
      publicKeySpkiB64: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key_spki_b64'],
      ),
      keyBackend: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_backend'],
      ),
      widgetEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}widget_enabled'],
      )!,
      llmProvider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}llm_provider'],
      )!,
      llmBaseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}llm_base_url'],
      ),
      llmApiKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}llm_api_key'],
      ),
      llmModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}llm_model'],
      ),
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSettingsRow extends DataClass implements Insertable<AppSettingsRow> {
  final int id;
  final String? lastHostId;
  final String? publicKeySpkiB64;
  final String? keyBackend;
  final bool widgetEnabled;
  final String llmProvider;
  final String? llmBaseUrl;
  final String? llmApiKey;
  final String? llmModel;
  const AppSettingsRow({
    required this.id,
    this.lastHostId,
    this.publicKeySpkiB64,
    this.keyBackend,
    required this.widgetEnabled,
    required this.llmProvider,
    this.llmBaseUrl,
    this.llmApiKey,
    this.llmModel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || lastHostId != null) {
      map['last_host_id'] = Variable<String>(lastHostId);
    }
    if (!nullToAbsent || publicKeySpkiB64 != null) {
      map['public_key_spki_b64'] = Variable<String>(publicKeySpkiB64);
    }
    if (!nullToAbsent || keyBackend != null) {
      map['key_backend'] = Variable<String>(keyBackend);
    }
    map['widget_enabled'] = Variable<bool>(widgetEnabled);
    map['llm_provider'] = Variable<String>(llmProvider);
    if (!nullToAbsent || llmBaseUrl != null) {
      map['llm_base_url'] = Variable<String>(llmBaseUrl);
    }
    if (!nullToAbsent || llmApiKey != null) {
      map['llm_api_key'] = Variable<String>(llmApiKey);
    }
    if (!nullToAbsent || llmModel != null) {
      map['llm_model'] = Variable<String>(llmModel);
    }
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      id: Value(id),
      lastHostId: lastHostId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastHostId),
      publicKeySpkiB64: publicKeySpkiB64 == null && nullToAbsent
          ? const Value.absent()
          : Value(publicKeySpkiB64),
      keyBackend: keyBackend == null && nullToAbsent
          ? const Value.absent()
          : Value(keyBackend),
      widgetEnabled: Value(widgetEnabled),
      llmProvider: Value(llmProvider),
      llmBaseUrl: llmBaseUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(llmBaseUrl),
      llmApiKey: llmApiKey == null && nullToAbsent
          ? const Value.absent()
          : Value(llmApiKey),
      llmModel: llmModel == null && nullToAbsent
          ? const Value.absent()
          : Value(llmModel),
    );
  }

  factory AppSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingsRow(
      id: serializer.fromJson<int>(json['id']),
      lastHostId: serializer.fromJson<String?>(json['lastHostId']),
      publicKeySpkiB64: serializer.fromJson<String?>(json['publicKeySpkiB64']),
      keyBackend: serializer.fromJson<String?>(json['keyBackend']),
      widgetEnabled: serializer.fromJson<bool>(json['widgetEnabled']),
      llmProvider: serializer.fromJson<String>(json['llmProvider']),
      llmBaseUrl: serializer.fromJson<String?>(json['llmBaseUrl']),
      llmApiKey: serializer.fromJson<String?>(json['llmApiKey']),
      llmModel: serializer.fromJson<String?>(json['llmModel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lastHostId': serializer.toJson<String?>(lastHostId),
      'publicKeySpkiB64': serializer.toJson<String?>(publicKeySpkiB64),
      'keyBackend': serializer.toJson<String?>(keyBackend),
      'widgetEnabled': serializer.toJson<bool>(widgetEnabled),
      'llmProvider': serializer.toJson<String>(llmProvider),
      'llmBaseUrl': serializer.toJson<String?>(llmBaseUrl),
      'llmApiKey': serializer.toJson<String?>(llmApiKey),
      'llmModel': serializer.toJson<String?>(llmModel),
    };
  }

  AppSettingsRow copyWith({
    int? id,
    Value<String?> lastHostId = const Value.absent(),
    Value<String?> publicKeySpkiB64 = const Value.absent(),
    Value<String?> keyBackend = const Value.absent(),
    bool? widgetEnabled,
    String? llmProvider,
    Value<String?> llmBaseUrl = const Value.absent(),
    Value<String?> llmApiKey = const Value.absent(),
    Value<String?> llmModel = const Value.absent(),
  }) => AppSettingsRow(
    id: id ?? this.id,
    lastHostId: lastHostId.present ? lastHostId.value : this.lastHostId,
    publicKeySpkiB64: publicKeySpkiB64.present
        ? publicKeySpkiB64.value
        : this.publicKeySpkiB64,
    keyBackend: keyBackend.present ? keyBackend.value : this.keyBackend,
    widgetEnabled: widgetEnabled ?? this.widgetEnabled,
    llmProvider: llmProvider ?? this.llmProvider,
    llmBaseUrl: llmBaseUrl.present ? llmBaseUrl.value : this.llmBaseUrl,
    llmApiKey: llmApiKey.present ? llmApiKey.value : this.llmApiKey,
    llmModel: llmModel.present ? llmModel.value : this.llmModel,
  );
  AppSettingsRow copyWithCompanion(AppSettingsCompanion data) {
    return AppSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      lastHostId: data.lastHostId.present
          ? data.lastHostId.value
          : this.lastHostId,
      publicKeySpkiB64: data.publicKeySpkiB64.present
          ? data.publicKeySpkiB64.value
          : this.publicKeySpkiB64,
      keyBackend: data.keyBackend.present
          ? data.keyBackend.value
          : this.keyBackend,
      widgetEnabled: data.widgetEnabled.present
          ? data.widgetEnabled.value
          : this.widgetEnabled,
      llmProvider: data.llmProvider.present
          ? data.llmProvider.value
          : this.llmProvider,
      llmBaseUrl: data.llmBaseUrl.present
          ? data.llmBaseUrl.value
          : this.llmBaseUrl,
      llmApiKey: data.llmApiKey.present ? data.llmApiKey.value : this.llmApiKey,
      llmModel: data.llmModel.present ? data.llmModel.value : this.llmModel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsRow(')
          ..write('id: $id, ')
          ..write('lastHostId: $lastHostId, ')
          ..write('publicKeySpkiB64: $publicKeySpkiB64, ')
          ..write('keyBackend: $keyBackend, ')
          ..write('widgetEnabled: $widgetEnabled, ')
          ..write('llmProvider: $llmProvider, ')
          ..write('llmBaseUrl: $llmBaseUrl, ')
          ..write('llmApiKey: $llmApiKey, ')
          ..write('llmModel: $llmModel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    lastHostId,
    publicKeySpkiB64,
    keyBackend,
    widgetEnabled,
    llmProvider,
    llmBaseUrl,
    llmApiKey,
    llmModel,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingsRow &&
          other.id == this.id &&
          other.lastHostId == this.lastHostId &&
          other.publicKeySpkiB64 == this.publicKeySpkiB64 &&
          other.keyBackend == this.keyBackend &&
          other.widgetEnabled == this.widgetEnabled &&
          other.llmProvider == this.llmProvider &&
          other.llmBaseUrl == this.llmBaseUrl &&
          other.llmApiKey == this.llmApiKey &&
          other.llmModel == this.llmModel);
}

class AppSettingsCompanion extends UpdateCompanion<AppSettingsRow> {
  final Value<int> id;
  final Value<String?> lastHostId;
  final Value<String?> publicKeySpkiB64;
  final Value<String?> keyBackend;
  final Value<bool> widgetEnabled;
  final Value<String> llmProvider;
  final Value<String?> llmBaseUrl;
  final Value<String?> llmApiKey;
  final Value<String?> llmModel;
  const AppSettingsCompanion({
    this.id = const Value.absent(),
    this.lastHostId = const Value.absent(),
    this.publicKeySpkiB64 = const Value.absent(),
    this.keyBackend = const Value.absent(),
    this.widgetEnabled = const Value.absent(),
    this.llmProvider = const Value.absent(),
    this.llmBaseUrl = const Value.absent(),
    this.llmApiKey = const Value.absent(),
    this.llmModel = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.lastHostId = const Value.absent(),
    this.publicKeySpkiB64 = const Value.absent(),
    this.keyBackend = const Value.absent(),
    this.widgetEnabled = const Value.absent(),
    this.llmProvider = const Value.absent(),
    this.llmBaseUrl = const Value.absent(),
    this.llmApiKey = const Value.absent(),
    this.llmModel = const Value.absent(),
  });
  static Insertable<AppSettingsRow> custom({
    Expression<int>? id,
    Expression<String>? lastHostId,
    Expression<String>? publicKeySpkiB64,
    Expression<String>? keyBackend,
    Expression<bool>? widgetEnabled,
    Expression<String>? llmProvider,
    Expression<String>? llmBaseUrl,
    Expression<String>? llmApiKey,
    Expression<String>? llmModel,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lastHostId != null) 'last_host_id': lastHostId,
      if (publicKeySpkiB64 != null) 'public_key_spki_b64': publicKeySpkiB64,
      if (keyBackend != null) 'key_backend': keyBackend,
      if (widgetEnabled != null) 'widget_enabled': widgetEnabled,
      if (llmProvider != null) 'llm_provider': llmProvider,
      if (llmBaseUrl != null) 'llm_base_url': llmBaseUrl,
      if (llmApiKey != null) 'llm_api_key': llmApiKey,
      if (llmModel != null) 'llm_model': llmModel,
    });
  }

  AppSettingsCompanion copyWith({
    Value<int>? id,
    Value<String?>? lastHostId,
    Value<String?>? publicKeySpkiB64,
    Value<String?>? keyBackend,
    Value<bool>? widgetEnabled,
    Value<String>? llmProvider,
    Value<String?>? llmBaseUrl,
    Value<String?>? llmApiKey,
    Value<String?>? llmModel,
  }) {
    return AppSettingsCompanion(
      id: id ?? this.id,
      lastHostId: lastHostId ?? this.lastHostId,
      publicKeySpkiB64: publicKeySpkiB64 ?? this.publicKeySpkiB64,
      keyBackend: keyBackend ?? this.keyBackend,
      widgetEnabled: widgetEnabled ?? this.widgetEnabled,
      llmProvider: llmProvider ?? this.llmProvider,
      llmBaseUrl: llmBaseUrl ?? this.llmBaseUrl,
      llmApiKey: llmApiKey ?? this.llmApiKey,
      llmModel: llmModel ?? this.llmModel,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lastHostId.present) {
      map['last_host_id'] = Variable<String>(lastHostId.value);
    }
    if (publicKeySpkiB64.present) {
      map['public_key_spki_b64'] = Variable<String>(publicKeySpkiB64.value);
    }
    if (keyBackend.present) {
      map['key_backend'] = Variable<String>(keyBackend.value);
    }
    if (widgetEnabled.present) {
      map['widget_enabled'] = Variable<bool>(widgetEnabled.value);
    }
    if (llmProvider.present) {
      map['llm_provider'] = Variable<String>(llmProvider.value);
    }
    if (llmBaseUrl.present) {
      map['llm_base_url'] = Variable<String>(llmBaseUrl.value);
    }
    if (llmApiKey.present) {
      map['llm_api_key'] = Variable<String>(llmApiKey.value);
    }
    if (llmModel.present) {
      map['llm_model'] = Variable<String>(llmModel.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('id: $id, ')
          ..write('lastHostId: $lastHostId, ')
          ..write('publicKeySpkiB64: $publicKeySpkiB64, ')
          ..write('keyBackend: $keyBackend, ')
          ..write('widgetEnabled: $widgetEnabled, ')
          ..write('llmProvider: $llmProvider, ')
          ..write('llmBaseUrl: $llmBaseUrl, ')
          ..write('llmApiKey: $llmApiKey, ')
          ..write('llmModel: $llmModel')
          ..write(')'))
        .toString();
  }
}

class $SearchIndexCacheTable extends SearchIndexCache
    with TableInfo<$SearchIndexCacheTable, SearchIndexRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchIndexCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _indexedAtMeta = const VerificationMeta(
    'indexedAt',
  );
  @override
  late final GeneratedColumn<DateTime> indexedAt = GeneratedColumn<DateTime>(
    'indexed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [hostId, kind, name, indexedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_index';
  @override
  VerificationContext validateIntegrity(
    Insertable<SearchIndexRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('indexed_at')) {
      context.handle(
        _indexedAtMeta,
        indexedAt.isAcceptableOrUnknown(data['indexed_at']!, _indexedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_indexedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hostId, kind, name};
  @override
  SearchIndexRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchIndexRow(
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      indexedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}indexed_at'],
      )!,
    );
  }

  @override
  $SearchIndexCacheTable createAlias(String alias) {
    return $SearchIndexCacheTable(attachedDatabase, alias);
  }
}

class SearchIndexRow extends DataClass implements Insertable<SearchIndexRow> {
  final String hostId;
  final String kind;
  final String name;
  final DateTime indexedAt;
  const SearchIndexRow({
    required this.hostId,
    required this.kind,
    required this.name,
    required this.indexedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['host_id'] = Variable<String>(hostId);
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    map['indexed_at'] = Variable<DateTime>(indexedAt);
    return map;
  }

  SearchIndexCacheCompanion toCompanion(bool nullToAbsent) {
    return SearchIndexCacheCompanion(
      hostId: Value(hostId),
      kind: Value(kind),
      name: Value(name),
      indexedAt: Value(indexedAt),
    );
  }

  factory SearchIndexRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SearchIndexRow(
      hostId: serializer.fromJson<String>(json['hostId']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      indexedAt: serializer.fromJson<DateTime>(json['indexedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hostId': serializer.toJson<String>(hostId),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'indexedAt': serializer.toJson<DateTime>(indexedAt),
    };
  }

  SearchIndexRow copyWith({
    String? hostId,
    String? kind,
    String? name,
    DateTime? indexedAt,
  }) => SearchIndexRow(
    hostId: hostId ?? this.hostId,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    indexedAt: indexedAt ?? this.indexedAt,
  );
  SearchIndexRow copyWithCompanion(SearchIndexCacheCompanion data) {
    return SearchIndexRow(
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      indexedAt: data.indexedAt.present ? data.indexedAt.value : this.indexedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchIndexRow(')
          ..write('hostId: $hostId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('indexedAt: $indexedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(hostId, kind, name, indexedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchIndexRow &&
          other.hostId == this.hostId &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.indexedAt == this.indexedAt);
}

class SearchIndexCacheCompanion extends UpdateCompanion<SearchIndexRow> {
  final Value<String> hostId;
  final Value<String> kind;
  final Value<String> name;
  final Value<DateTime> indexedAt;
  final Value<int> rowid;
  const SearchIndexCacheCompanion({
    this.hostId = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.indexedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SearchIndexCacheCompanion.insert({
    required String hostId,
    required String kind,
    required String name,
    required DateTime indexedAt,
    this.rowid = const Value.absent(),
  }) : hostId = Value(hostId),
       kind = Value(kind),
       name = Value(name),
       indexedAt = Value(indexedAt);
  static Insertable<SearchIndexRow> custom({
    Expression<String>? hostId,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<DateTime>? indexedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (hostId != null) 'host_id': hostId,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (indexedAt != null) 'indexed_at': indexedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SearchIndexCacheCompanion copyWith({
    Value<String>? hostId,
    Value<String>? kind,
    Value<String>? name,
    Value<DateTime>? indexedAt,
    Value<int>? rowid,
  }) {
    return SearchIndexCacheCompanion(
      hostId: hostId ?? this.hostId,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      indexedAt: indexedAt ?? this.indexedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (indexedAt.present) {
      map['indexed_at'] = Variable<DateTime>(indexedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchIndexCacheCompanion(')
          ..write('hostId: $hostId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('indexedAt: $indexedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SnippetsTable extends Snippets
    with TableInfo<$SnippetsTable, SnippetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SnippetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateMeta = const VerificationMeta(
    'template',
  );
  @override
  late final GeneratedColumn<String> template = GeneratedColumn<String>(
    'template',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _starterMeta = const VerificationMeta(
    'starter',
  );
  @override
  late final GeneratedColumn<bool> starter = GeneratedColumn<bool>(
    'starter',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("starter" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    template,
    starter,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snippets';
  @override
  VerificationContext validateIntegrity(
    Insertable<SnippetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('template')) {
      context.handle(
        _templateMeta,
        template.isAcceptableOrUnknown(data['template']!, _templateMeta),
      );
    } else if (isInserting) {
      context.missing(_templateMeta);
    }
    if (data.containsKey('starter')) {
      context.handle(
        _starterMeta,
        starter.isAcceptableOrUnknown(data['starter']!, _starterMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SnippetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnippetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      template: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template'],
      )!,
      starter: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}starter'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SnippetsTable createAlias(String alias) {
    return $SnippetsTable(attachedDatabase, alias);
  }
}

class SnippetRow extends DataClass implements Insertable<SnippetRow> {
  final String id;
  final String name;
  final String template;
  final bool starter;
  final DateTime updatedAt;
  const SnippetRow({
    required this.id,
    required this.name,
    required this.template,
    required this.starter,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['template'] = Variable<String>(template);
    map['starter'] = Variable<bool>(starter);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SnippetsCompanion toCompanion(bool nullToAbsent) {
    return SnippetsCompanion(
      id: Value(id),
      name: Value(name),
      template: Value(template),
      starter: Value(starter),
      updatedAt: Value(updatedAt),
    );
  }

  factory SnippetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnippetRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      template: serializer.fromJson<String>(json['template']),
      starter: serializer.fromJson<bool>(json['starter']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'template': serializer.toJson<String>(template),
      'starter': serializer.toJson<bool>(starter),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SnippetRow copyWith({
    String? id,
    String? name,
    String? template,
    bool? starter,
    DateTime? updatedAt,
  }) => SnippetRow(
    id: id ?? this.id,
    name: name ?? this.name,
    template: template ?? this.template,
    starter: starter ?? this.starter,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SnippetRow copyWithCompanion(SnippetsCompanion data) {
    return SnippetRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      template: data.template.present ? data.template.value : this.template,
      starter: data.starter.present ? data.starter.value : this.starter,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnippetRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('template: $template, ')
          ..write('starter: $starter, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, template, starter, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnippetRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.template == this.template &&
          other.starter == this.starter &&
          other.updatedAt == this.updatedAt);
}

class SnippetsCompanion extends UpdateCompanion<SnippetRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> template;
  final Value<bool> starter;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SnippetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.template = const Value.absent(),
    this.starter = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnippetsCompanion.insert({
    required String id,
    required String name,
    required String template,
    this.starter = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       template = Value(template),
       updatedAt = Value(updatedAt);
  static Insertable<SnippetRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? template,
    Expression<bool>? starter,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (template != null) 'template': template,
      if (starter != null) 'starter': starter,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnippetsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? template,
    Value<bool>? starter,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SnippetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      template: template ?? this.template,
      starter: starter ?? this.starter,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (template.present) {
      map['template'] = Variable<String>(template.value);
    }
    if (starter.present) {
      map['starter'] = Variable<bool>(starter.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnippetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('template: $template, ')
          ..write('starter: $starter, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HostTagsTable extends HostTags
    with TableInfo<$HostTagsTable, HostTagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HostTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [hostId, tag];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'host_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<HostTagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    } else if (isInserting) {
      context.missing(_tagMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hostId, tag};
  @override
  HostTagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HostTagRow(
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      )!,
    );
  }

  @override
  $HostTagsTable createAlias(String alias) {
    return $HostTagsTable(attachedDatabase, alias);
  }
}

class HostTagRow extends DataClass implements Insertable<HostTagRow> {
  final String hostId;
  final String tag;
  const HostTagRow({required this.hostId, required this.tag});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['host_id'] = Variable<String>(hostId);
    map['tag'] = Variable<String>(tag);
    return map;
  }

  HostTagsCompanion toCompanion(bool nullToAbsent) {
    return HostTagsCompanion(hostId: Value(hostId), tag: Value(tag));
  }

  factory HostTagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HostTagRow(
      hostId: serializer.fromJson<String>(json['hostId']),
      tag: serializer.fromJson<String>(json['tag']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hostId': serializer.toJson<String>(hostId),
      'tag': serializer.toJson<String>(tag),
    };
  }

  HostTagRow copyWith({String? hostId, String? tag}) =>
      HostTagRow(hostId: hostId ?? this.hostId, tag: tag ?? this.tag);
  HostTagRow copyWithCompanion(HostTagsCompanion data) {
    return HostTagRow(
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      tag: data.tag.present ? data.tag.value : this.tag,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HostTagRow(')
          ..write('hostId: $hostId, ')
          ..write('tag: $tag')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(hostId, tag);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostTagRow &&
          other.hostId == this.hostId &&
          other.tag == this.tag);
}

class HostTagsCompanion extends UpdateCompanion<HostTagRow> {
  final Value<String> hostId;
  final Value<String> tag;
  final Value<int> rowid;
  const HostTagsCompanion({
    this.hostId = const Value.absent(),
    this.tag = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HostTagsCompanion.insert({
    required String hostId,
    required String tag,
    this.rowid = const Value.absent(),
  }) : hostId = Value(hostId),
       tag = Value(tag);
  static Insertable<HostTagRow> custom({
    Expression<String>? hostId,
    Expression<String>? tag,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (hostId != null) 'host_id': hostId,
      if (tag != null) 'tag': tag,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HostTagsCompanion copyWith({
    Value<String>? hostId,
    Value<String>? tag,
    Value<int>? rowid,
  }) {
    return HostTagsCompanion(
      hostId: hostId ?? this.hostId,
      tag: tag ?? this.tag,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HostTagsCompanion(')
          ..write('hostId: $hostId, ')
          ..write('tag: $tag, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FleetCacheTable extends FleetCache
    with TableInfo<$FleetCacheTable, FleetCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FleetCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hostIdMeta = const VerificationMeta('hostId');
  @override
  late final GeneratedColumn<String> hostId = GeneratedColumn<String>(
    'host_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reachableMeta = const VerificationMeta(
    'reachable',
  );
  @override
  late final GeneratedColumn<bool> reachable = GeneratedColumn<bool>(
    'reachable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reachable" IN (0, 1))',
    ),
  );
  static const VerificationMeta _load1Meta = const VerificationMeta('load1');
  @override
  late final GeneratedColumn<double> load1 = GeneratedColumn<double>(
    'load1',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _diskRootPercentMeta = const VerificationMeta(
    'diskRootPercent',
  );
  @override
  late final GeneratedColumn<int> diskRootPercent = GeneratedColumn<int>(
    'disk_root_percent',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _failedUnitCountMeta = const VerificationMeta(
    'failedUnitCount',
  );
  @override
  late final GeneratedColumn<int> failedUnitCount = GeneratedColumn<int>(
    'failed_unit_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pendingUpdatesMeta = const VerificationMeta(
    'pendingUpdates',
  );
  @override
  late final GeneratedColumn<int> pendingUpdates = GeneratedColumn<int>(
    'pending_updates',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    hostId,
    reachable,
    load1,
    diskRootPercent,
    failedUnitCount,
    pendingUpdates,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fleet_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<FleetCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('host_id')) {
      context.handle(
        _hostIdMeta,
        hostId.isAcceptableOrUnknown(data['host_id']!, _hostIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hostIdMeta);
    }
    if (data.containsKey('reachable')) {
      context.handle(
        _reachableMeta,
        reachable.isAcceptableOrUnknown(data['reachable']!, _reachableMeta),
      );
    } else if (isInserting) {
      context.missing(_reachableMeta);
    }
    if (data.containsKey('load1')) {
      context.handle(
        _load1Meta,
        load1.isAcceptableOrUnknown(data['load1']!, _load1Meta),
      );
    } else if (isInserting) {
      context.missing(_load1Meta);
    }
    if (data.containsKey('disk_root_percent')) {
      context.handle(
        _diskRootPercentMeta,
        diskRootPercent.isAcceptableOrUnknown(
          data['disk_root_percent']!,
          _diskRootPercentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_diskRootPercentMeta);
    }
    if (data.containsKey('failed_unit_count')) {
      context.handle(
        _failedUnitCountMeta,
        failedUnitCount.isAcceptableOrUnknown(
          data['failed_unit_count']!,
          _failedUnitCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_failedUnitCountMeta);
    }
    if (data.containsKey('pending_updates')) {
      context.handle(
        _pendingUpdatesMeta,
        pendingUpdates.isAcceptableOrUnknown(
          data['pending_updates']!,
          _pendingUpdatesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pendingUpdatesMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hostId};
  @override
  FleetCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FleetCacheRow(
      hostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_id'],
      )!,
      reachable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reachable'],
      )!,
      load1: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}load1'],
      )!,
      diskRootPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disk_root_percent'],
      )!,
      failedUnitCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failed_unit_count'],
      )!,
      pendingUpdates: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pending_updates'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $FleetCacheTable createAlias(String alias) {
    return $FleetCacheTable(attachedDatabase, alias);
  }
}

class FleetCacheRow extends DataClass implements Insertable<FleetCacheRow> {
  final String hostId;
  final bool reachable;
  final double load1;
  final int diskRootPercent;
  final int failedUnitCount;
  final int pendingUpdates;
  final DateTime fetchedAt;
  const FleetCacheRow({
    required this.hostId,
    required this.reachable,
    required this.load1,
    required this.diskRootPercent,
    required this.failedUnitCount,
    required this.pendingUpdates,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['host_id'] = Variable<String>(hostId);
    map['reachable'] = Variable<bool>(reachable);
    map['load1'] = Variable<double>(load1);
    map['disk_root_percent'] = Variable<int>(diskRootPercent);
    map['failed_unit_count'] = Variable<int>(failedUnitCount);
    map['pending_updates'] = Variable<int>(pendingUpdates);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  FleetCacheCompanion toCompanion(bool nullToAbsent) {
    return FleetCacheCompanion(
      hostId: Value(hostId),
      reachable: Value(reachable),
      load1: Value(load1),
      diskRootPercent: Value(diskRootPercent),
      failedUnitCount: Value(failedUnitCount),
      pendingUpdates: Value(pendingUpdates),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory FleetCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FleetCacheRow(
      hostId: serializer.fromJson<String>(json['hostId']),
      reachable: serializer.fromJson<bool>(json['reachable']),
      load1: serializer.fromJson<double>(json['load1']),
      diskRootPercent: serializer.fromJson<int>(json['diskRootPercent']),
      failedUnitCount: serializer.fromJson<int>(json['failedUnitCount']),
      pendingUpdates: serializer.fromJson<int>(json['pendingUpdates']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hostId': serializer.toJson<String>(hostId),
      'reachable': serializer.toJson<bool>(reachable),
      'load1': serializer.toJson<double>(load1),
      'diskRootPercent': serializer.toJson<int>(diskRootPercent),
      'failedUnitCount': serializer.toJson<int>(failedUnitCount),
      'pendingUpdates': serializer.toJson<int>(pendingUpdates),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  FleetCacheRow copyWith({
    String? hostId,
    bool? reachable,
    double? load1,
    int? diskRootPercent,
    int? failedUnitCount,
    int? pendingUpdates,
    DateTime? fetchedAt,
  }) => FleetCacheRow(
    hostId: hostId ?? this.hostId,
    reachable: reachable ?? this.reachable,
    load1: load1 ?? this.load1,
    diskRootPercent: diskRootPercent ?? this.diskRootPercent,
    failedUnitCount: failedUnitCount ?? this.failedUnitCount,
    pendingUpdates: pendingUpdates ?? this.pendingUpdates,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  FleetCacheRow copyWithCompanion(FleetCacheCompanion data) {
    return FleetCacheRow(
      hostId: data.hostId.present ? data.hostId.value : this.hostId,
      reachable: data.reachable.present ? data.reachable.value : this.reachable,
      load1: data.load1.present ? data.load1.value : this.load1,
      diskRootPercent: data.diskRootPercent.present
          ? data.diskRootPercent.value
          : this.diskRootPercent,
      failedUnitCount: data.failedUnitCount.present
          ? data.failedUnitCount.value
          : this.failedUnitCount,
      pendingUpdates: data.pendingUpdates.present
          ? data.pendingUpdates.value
          : this.pendingUpdates,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FleetCacheRow(')
          ..write('hostId: $hostId, ')
          ..write('reachable: $reachable, ')
          ..write('load1: $load1, ')
          ..write('diskRootPercent: $diskRootPercent, ')
          ..write('failedUnitCount: $failedUnitCount, ')
          ..write('pendingUpdates: $pendingUpdates, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    hostId,
    reachable,
    load1,
    diskRootPercent,
    failedUnitCount,
    pendingUpdates,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FleetCacheRow &&
          other.hostId == this.hostId &&
          other.reachable == this.reachable &&
          other.load1 == this.load1 &&
          other.diskRootPercent == this.diskRootPercent &&
          other.failedUnitCount == this.failedUnitCount &&
          other.pendingUpdates == this.pendingUpdates &&
          other.fetchedAt == this.fetchedAt);
}

class FleetCacheCompanion extends UpdateCompanion<FleetCacheRow> {
  final Value<String> hostId;
  final Value<bool> reachable;
  final Value<double> load1;
  final Value<int> diskRootPercent;
  final Value<int> failedUnitCount;
  final Value<int> pendingUpdates;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const FleetCacheCompanion({
    this.hostId = const Value.absent(),
    this.reachable = const Value.absent(),
    this.load1 = const Value.absent(),
    this.diskRootPercent = const Value.absent(),
    this.failedUnitCount = const Value.absent(),
    this.pendingUpdates = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FleetCacheCompanion.insert({
    required String hostId,
    required bool reachable,
    required double load1,
    required int diskRootPercent,
    required int failedUnitCount,
    required int pendingUpdates,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : hostId = Value(hostId),
       reachable = Value(reachable),
       load1 = Value(load1),
       diskRootPercent = Value(diskRootPercent),
       failedUnitCount = Value(failedUnitCount),
       pendingUpdates = Value(pendingUpdates),
       fetchedAt = Value(fetchedAt);
  static Insertable<FleetCacheRow> custom({
    Expression<String>? hostId,
    Expression<bool>? reachable,
    Expression<double>? load1,
    Expression<int>? diskRootPercent,
    Expression<int>? failedUnitCount,
    Expression<int>? pendingUpdates,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (hostId != null) 'host_id': hostId,
      if (reachable != null) 'reachable': reachable,
      if (load1 != null) 'load1': load1,
      if (diskRootPercent != null) 'disk_root_percent': diskRootPercent,
      if (failedUnitCount != null) 'failed_unit_count': failedUnitCount,
      if (pendingUpdates != null) 'pending_updates': pendingUpdates,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FleetCacheCompanion copyWith({
    Value<String>? hostId,
    Value<bool>? reachable,
    Value<double>? load1,
    Value<int>? diskRootPercent,
    Value<int>? failedUnitCount,
    Value<int>? pendingUpdates,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return FleetCacheCompanion(
      hostId: hostId ?? this.hostId,
      reachable: reachable ?? this.reachable,
      load1: load1 ?? this.load1,
      diskRootPercent: diskRootPercent ?? this.diskRootPercent,
      failedUnitCount: failedUnitCount ?? this.failedUnitCount,
      pendingUpdates: pendingUpdates ?? this.pendingUpdates,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hostId.present) {
      map['host_id'] = Variable<String>(hostId.value);
    }
    if (reachable.present) {
      map['reachable'] = Variable<bool>(reachable.value);
    }
    if (load1.present) {
      map['load1'] = Variable<double>(load1.value);
    }
    if (diskRootPercent.present) {
      map['disk_root_percent'] = Variable<int>(diskRootPercent.value);
    }
    if (failedUnitCount.present) {
      map['failed_unit_count'] = Variable<int>(failedUnitCount.value);
    }
    if (pendingUpdates.present) {
      map['pending_updates'] = Variable<int>(pendingUpdates.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FleetCacheCompanion(')
          ..write('hostId: $hostId, ')
          ..write('reachable: $reachable, ')
          ..write('load1: $load1, ')
          ..write('diskRootPercent: $diskRootPercent, ')
          ..write('failedUnitCount: $failedUnitCount, ')
          ..write('pendingUpdates: $pendingUpdates, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$KelolaDatabase extends GeneratedDatabase {
  _$KelolaDatabase(QueryExecutor e) : super(e);
  $KelolaDatabaseManager get managers => $KelolaDatabaseManager(this);
  late final $HostsTable hosts = $HostsTable(this);
  late final $HostKeysTable hostKeys = $HostKeysTable(this);
  late final $CachedFactsTable cachedFacts = $CachedFactsTable(this);
  late final $RecentsTable recents = $RecentsTable(this);
  late final $PinsTable pins = $PinsTable(this);
  late final $AuditRecordsTable auditRecords = $AuditRecordsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $SearchIndexCacheTable searchIndexCache = $SearchIndexCacheTable(
    this,
  );
  late final $SnippetsTable snippets = $SnippetsTable(this);
  late final $HostTagsTable hostTags = $HostTagsTable(this);
  late final $FleetCacheTable fleetCache = $FleetCacheTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    hosts,
    hostKeys,
    cachedFacts,
    recents,
    pins,
    auditRecords,
    appSettings,
    searchIndexCache,
    snippets,
    hostTags,
    fleetCache,
  ];
}

typedef $$HostsTableCreateCompanionBuilder =
    HostsCompanion Function({
      required String id,
      required String alias,
      required String address,
      Value<int> port,
      required String username,
      required String keyAlias,
      Value<String?> jumpHostId,
      Value<bool> readOnly,
      Value<int> sortOrder,
      Value<String?> note,
      Value<int?> lastRttMs,
      Value<String> attention,
      Value<int?> failedUnitCount,
      Value<int?> diskRootPercent,
      Value<DateTime?> attentionAt,
      Value<DateTime?> lastSeenAt,
      required DateTime createdAt,
      Value<bool> sudoNeedsPassword,
      Value<int> rowid,
    });
typedef $$HostsTableUpdateCompanionBuilder =
    HostsCompanion Function({
      Value<String> id,
      Value<String> alias,
      Value<String> address,
      Value<int> port,
      Value<String> username,
      Value<String> keyAlias,
      Value<String?> jumpHostId,
      Value<bool> readOnly,
      Value<int> sortOrder,
      Value<String?> note,
      Value<int?> lastRttMs,
      Value<String> attention,
      Value<int?> failedUnitCount,
      Value<int?> diskRootPercent,
      Value<DateTime?> attentionAt,
      Value<DateTime?> lastSeenAt,
      Value<DateTime> createdAt,
      Value<bool> sudoNeedsPassword,
      Value<int> rowid,
    });

class $$HostsTableFilterComposer
    extends Composer<_$KelolaDatabase, $HostsTable> {
  $$HostsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyAlias => $composableBuilder(
    column: $table.keyAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jumpHostId => $composableBuilder(
    column: $table.jumpHostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get readOnly => $composableBuilder(
    column: $table.readOnly,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastRttMs => $composableBuilder(
    column: $table.lastRttMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attention => $composableBuilder(
    column: $table.attention,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failedUnitCount => $composableBuilder(
    column: $table.failedUnitCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get diskRootPercent => $composableBuilder(
    column: $table.diskRootPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get attentionAt => $composableBuilder(
    column: $table.attentionAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sudoNeedsPassword => $composableBuilder(
    column: $table.sudoNeedsPassword,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HostsTableOrderingComposer
    extends Composer<_$KelolaDatabase, $HostsTable> {
  $$HostsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyAlias => $composableBuilder(
    column: $table.keyAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jumpHostId => $composableBuilder(
    column: $table.jumpHostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get readOnly => $composableBuilder(
    column: $table.readOnly,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastRttMs => $composableBuilder(
    column: $table.lastRttMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attention => $composableBuilder(
    column: $table.attention,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failedUnitCount => $composableBuilder(
    column: $table.failedUnitCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get diskRootPercent => $composableBuilder(
    column: $table.diskRootPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get attentionAt => $composableBuilder(
    column: $table.attentionAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sudoNeedsPassword => $composableBuilder(
    column: $table.sudoNeedsPassword,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HostsTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $HostsTable> {
  $$HostsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get keyAlias =>
      $composableBuilder(column: $table.keyAlias, builder: (column) => column);

  GeneratedColumn<String> get jumpHostId => $composableBuilder(
    column: $table.jumpHostId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get readOnly =>
      $composableBuilder(column: $table.readOnly, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get lastRttMs =>
      $composableBuilder(column: $table.lastRttMs, builder: (column) => column);

  GeneratedColumn<String> get attention =>
      $composableBuilder(column: $table.attention, builder: (column) => column);

  GeneratedColumn<int> get failedUnitCount => $composableBuilder(
    column: $table.failedUnitCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get diskRootPercent => $composableBuilder(
    column: $table.diskRootPercent,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get attentionAt => $composableBuilder(
    column: $table.attentionAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get sudoNeedsPassword => $composableBuilder(
    column: $table.sudoNeedsPassword,
    builder: (column) => column,
  );
}

class $$HostsTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $HostsTable,
          HostRow,
          $$HostsTableFilterComposer,
          $$HostsTableOrderingComposer,
          $$HostsTableAnnotationComposer,
          $$HostsTableCreateCompanionBuilder,
          $$HostsTableUpdateCompanionBuilder,
          (HostRow, BaseReferences<_$KelolaDatabase, $HostsTable, HostRow>),
          HostRow,
          PrefetchHooks Function()
        > {
  $$HostsTableTableManager(_$KelolaDatabase db, $HostsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HostsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HostsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HostsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> alias = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> keyAlias = const Value.absent(),
                Value<String?> jumpHostId = const Value.absent(),
                Value<bool> readOnly = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int?> lastRttMs = const Value.absent(),
                Value<String> attention = const Value.absent(),
                Value<int?> failedUnitCount = const Value.absent(),
                Value<int?> diskRootPercent = const Value.absent(),
                Value<DateTime?> attentionAt = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> sudoNeedsPassword = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostsCompanion(
                id: id,
                alias: alias,
                address: address,
                port: port,
                username: username,
                keyAlias: keyAlias,
                jumpHostId: jumpHostId,
                readOnly: readOnly,
                sortOrder: sortOrder,
                note: note,
                lastRttMs: lastRttMs,
                attention: attention,
                failedUnitCount: failedUnitCount,
                diskRootPercent: diskRootPercent,
                attentionAt: attentionAt,
                lastSeenAt: lastSeenAt,
                createdAt: createdAt,
                sudoNeedsPassword: sudoNeedsPassword,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String alias,
                required String address,
                Value<int> port = const Value.absent(),
                required String username,
                required String keyAlias,
                Value<String?> jumpHostId = const Value.absent(),
                Value<bool> readOnly = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int?> lastRttMs = const Value.absent(),
                Value<String> attention = const Value.absent(),
                Value<int?> failedUnitCount = const Value.absent(),
                Value<int?> diskRootPercent = const Value.absent(),
                Value<DateTime?> attentionAt = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                required DateTime createdAt,
                Value<bool> sudoNeedsPassword = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostsCompanion.insert(
                id: id,
                alias: alias,
                address: address,
                port: port,
                username: username,
                keyAlias: keyAlias,
                jumpHostId: jumpHostId,
                readOnly: readOnly,
                sortOrder: sortOrder,
                note: note,
                lastRttMs: lastRttMs,
                attention: attention,
                failedUnitCount: failedUnitCount,
                diskRootPercent: diskRootPercent,
                attentionAt: attentionAt,
                lastSeenAt: lastSeenAt,
                createdAt: createdAt,
                sudoNeedsPassword: sudoNeedsPassword,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HostsTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $HostsTable,
      HostRow,
      $$HostsTableFilterComposer,
      $$HostsTableOrderingComposer,
      $$HostsTableAnnotationComposer,
      $$HostsTableCreateCompanionBuilder,
      $$HostsTableUpdateCompanionBuilder,
      (HostRow, BaseReferences<_$KelolaDatabase, $HostsTable, HostRow>),
      HostRow,
      PrefetchHooks Function()
    >;
typedef $$HostKeysTableCreateCompanionBuilder =
    HostKeysCompanion Function({
      required String hostId,
      required String algorithm,
      required String fingerprint,
      required DateTime pinnedAt,
      Value<int> rowid,
    });
typedef $$HostKeysTableUpdateCompanionBuilder =
    HostKeysCompanion Function({
      Value<String> hostId,
      Value<String> algorithm,
      Value<String> fingerprint,
      Value<DateTime> pinnedAt,
      Value<int> rowid,
    });

class $$HostKeysTableFilterComposer
    extends Composer<_$KelolaDatabase, $HostKeysTable> {
  $$HostKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get algorithm => $composableBuilder(
    column: $table.algorithm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HostKeysTableOrderingComposer
    extends Composer<_$KelolaDatabase, $HostKeysTable> {
  $$HostKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get algorithm => $composableBuilder(
    column: $table.algorithm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HostKeysTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $HostKeysTable> {
  $$HostKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get algorithm =>
      $composableBuilder(column: $table.algorithm, builder: (column) => column);

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);
}

class $$HostKeysTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $HostKeysTable,
          HostKeyRow,
          $$HostKeysTableFilterComposer,
          $$HostKeysTableOrderingComposer,
          $$HostKeysTableAnnotationComposer,
          $$HostKeysTableCreateCompanionBuilder,
          $$HostKeysTableUpdateCompanionBuilder,
          (
            HostKeyRow,
            BaseReferences<_$KelolaDatabase, $HostKeysTable, HostKeyRow>,
          ),
          HostKeyRow,
          PrefetchHooks Function()
        > {
  $$HostKeysTableTableManager(_$KelolaDatabase db, $HostKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HostKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HostKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HostKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> hostId = const Value.absent(),
                Value<String> algorithm = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<DateTime> pinnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostKeysCompanion(
                hostId: hostId,
                algorithm: algorithm,
                fingerprint: fingerprint,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String hostId,
                required String algorithm,
                required String fingerprint,
                required DateTime pinnedAt,
                Value<int> rowid = const Value.absent(),
              }) => HostKeysCompanion.insert(
                hostId: hostId,
                algorithm: algorithm,
                fingerprint: fingerprint,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HostKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $HostKeysTable,
      HostKeyRow,
      $$HostKeysTableFilterComposer,
      $$HostKeysTableOrderingComposer,
      $$HostKeysTableAnnotationComposer,
      $$HostKeysTableCreateCompanionBuilder,
      $$HostKeysTableUpdateCompanionBuilder,
      (
        HostKeyRow,
        BaseReferences<_$KelolaDatabase, $HostKeysTable, HostKeyRow>,
      ),
      HostKeyRow,
      PrefetchHooks Function()
    >;
typedef $$CachedFactsTableCreateCompanionBuilder =
    CachedFactsCompanion Function({
      required String hostId,
      required String osId,
      required String osVersionId,
      Value<String?> prettyName,
      required String initSystem,
      Value<int?> systemdVersion,
      required String pkg,
      required String fw,
      required bool hasJournald,
      required bool journalReadable,
      required String arch,
      required DateTime discoveredAt,
      Value<int> rowid,
    });
typedef $$CachedFactsTableUpdateCompanionBuilder =
    CachedFactsCompanion Function({
      Value<String> hostId,
      Value<String> osId,
      Value<String> osVersionId,
      Value<String?> prettyName,
      Value<String> initSystem,
      Value<int?> systemdVersion,
      Value<String> pkg,
      Value<String> fw,
      Value<bool> hasJournald,
      Value<bool> journalReadable,
      Value<String> arch,
      Value<DateTime> discoveredAt,
      Value<int> rowid,
    });

class $$CachedFactsTableFilterComposer
    extends Composer<_$KelolaDatabase, $CachedFactsTable> {
  $$CachedFactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get osId => $composableBuilder(
    column: $table.osId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get osVersionId => $composableBuilder(
    column: $table.osVersionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prettyName => $composableBuilder(
    column: $table.prettyName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get initSystem => $composableBuilder(
    column: $table.initSystem,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get systemdVersion => $composableBuilder(
    column: $table.systemdVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pkg => $composableBuilder(
    column: $table.pkg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fw => $composableBuilder(
    column: $table.fw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasJournald => $composableBuilder(
    column: $table.hasJournald,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get journalReadable => $composableBuilder(
    column: $table.journalReadable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get arch => $composableBuilder(
    column: $table.arch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedFactsTableOrderingComposer
    extends Composer<_$KelolaDatabase, $CachedFactsTable> {
  $$CachedFactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get osId => $composableBuilder(
    column: $table.osId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get osVersionId => $composableBuilder(
    column: $table.osVersionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prettyName => $composableBuilder(
    column: $table.prettyName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get initSystem => $composableBuilder(
    column: $table.initSystem,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get systemdVersion => $composableBuilder(
    column: $table.systemdVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pkg => $composableBuilder(
    column: $table.pkg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fw => $composableBuilder(
    column: $table.fw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasJournald => $composableBuilder(
    column: $table.hasJournald,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get journalReadable => $composableBuilder(
    column: $table.journalReadable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get arch => $composableBuilder(
    column: $table.arch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedFactsTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $CachedFactsTable> {
  $$CachedFactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get osId =>
      $composableBuilder(column: $table.osId, builder: (column) => column);

  GeneratedColumn<String> get osVersionId => $composableBuilder(
    column: $table.osVersionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get prettyName => $composableBuilder(
    column: $table.prettyName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get initSystem => $composableBuilder(
    column: $table.initSystem,
    builder: (column) => column,
  );

  GeneratedColumn<int> get systemdVersion => $composableBuilder(
    column: $table.systemdVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pkg =>
      $composableBuilder(column: $table.pkg, builder: (column) => column);

  GeneratedColumn<String> get fw =>
      $composableBuilder(column: $table.fw, builder: (column) => column);

  GeneratedColumn<bool> get hasJournald => $composableBuilder(
    column: $table.hasJournald,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get journalReadable => $composableBuilder(
    column: $table.journalReadable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get arch =>
      $composableBuilder(column: $table.arch, builder: (column) => column);

  GeneratedColumn<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => column,
  );
}

class $$CachedFactsTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $CachedFactsTable,
          CachedFactsRow,
          $$CachedFactsTableFilterComposer,
          $$CachedFactsTableOrderingComposer,
          $$CachedFactsTableAnnotationComposer,
          $$CachedFactsTableCreateCompanionBuilder,
          $$CachedFactsTableUpdateCompanionBuilder,
          (
            CachedFactsRow,
            BaseReferences<_$KelolaDatabase, $CachedFactsTable, CachedFactsRow>,
          ),
          CachedFactsRow,
          PrefetchHooks Function()
        > {
  $$CachedFactsTableTableManager(_$KelolaDatabase db, $CachedFactsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedFactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedFactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedFactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> hostId = const Value.absent(),
                Value<String> osId = const Value.absent(),
                Value<String> osVersionId = const Value.absent(),
                Value<String?> prettyName = const Value.absent(),
                Value<String> initSystem = const Value.absent(),
                Value<int?> systemdVersion = const Value.absent(),
                Value<String> pkg = const Value.absent(),
                Value<String> fw = const Value.absent(),
                Value<bool> hasJournald = const Value.absent(),
                Value<bool> journalReadable = const Value.absent(),
                Value<String> arch = const Value.absent(),
                Value<DateTime> discoveredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedFactsCompanion(
                hostId: hostId,
                osId: osId,
                osVersionId: osVersionId,
                prettyName: prettyName,
                initSystem: initSystem,
                systemdVersion: systemdVersion,
                pkg: pkg,
                fw: fw,
                hasJournald: hasJournald,
                journalReadable: journalReadable,
                arch: arch,
                discoveredAt: discoveredAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String hostId,
                required String osId,
                required String osVersionId,
                Value<String?> prettyName = const Value.absent(),
                required String initSystem,
                Value<int?> systemdVersion = const Value.absent(),
                required String pkg,
                required String fw,
                required bool hasJournald,
                required bool journalReadable,
                required String arch,
                required DateTime discoveredAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedFactsCompanion.insert(
                hostId: hostId,
                osId: osId,
                osVersionId: osVersionId,
                prettyName: prettyName,
                initSystem: initSystem,
                systemdVersion: systemdVersion,
                pkg: pkg,
                fw: fw,
                hasJournald: hasJournald,
                journalReadable: journalReadable,
                arch: arch,
                discoveredAt: discoveredAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedFactsTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $CachedFactsTable,
      CachedFactsRow,
      $$CachedFactsTableFilterComposer,
      $$CachedFactsTableOrderingComposer,
      $$CachedFactsTableAnnotationComposer,
      $$CachedFactsTableCreateCompanionBuilder,
      $$CachedFactsTableUpdateCompanionBuilder,
      (
        CachedFactsRow,
        BaseReferences<_$KelolaDatabase, $CachedFactsTable, CachedFactsRow>,
      ),
      CachedFactsRow,
      PrefetchHooks Function()
    >;
typedef $$RecentsTableCreateCompanionBuilder =
    RecentsCompanion Function({
      Value<int> id,
      required String kind,
      required String hostId,
      required String label,
      required DateTime viewedAt,
    });
typedef $$RecentsTableUpdateCompanionBuilder =
    RecentsCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<String> hostId,
      Value<String> label,
      Value<DateTime> viewedAt,
    });

class $$RecentsTableFilterComposer
    extends Composer<_$KelolaDatabase, $RecentsTable> {
  $$RecentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get viewedAt => $composableBuilder(
    column: $table.viewedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecentsTableOrderingComposer
    extends Composer<_$KelolaDatabase, $RecentsTable> {
  $$RecentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get viewedAt => $composableBuilder(
    column: $table.viewedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecentsTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $RecentsTable> {
  $$RecentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<DateTime> get viewedAt =>
      $composableBuilder(column: $table.viewedAt, builder: (column) => column);
}

class $$RecentsTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $RecentsTable,
          RecentRow,
          $$RecentsTableFilterComposer,
          $$RecentsTableOrderingComposer,
          $$RecentsTableAnnotationComposer,
          $$RecentsTableCreateCompanionBuilder,
          $$RecentsTableUpdateCompanionBuilder,
          (
            RecentRow,
            BaseReferences<_$KelolaDatabase, $RecentsTable, RecentRow>,
          ),
          RecentRow,
          PrefetchHooks Function()
        > {
  $$RecentsTableTableManager(_$KelolaDatabase db, $RecentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> hostId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<DateTime> viewedAt = const Value.absent(),
              }) => RecentsCompanion(
                id: id,
                kind: kind,
                hostId: hostId,
                label: label,
                viewedAt: viewedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                required String hostId,
                required String label,
                required DateTime viewedAt,
              }) => RecentsCompanion.insert(
                id: id,
                kind: kind,
                hostId: hostId,
                label: label,
                viewedAt: viewedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecentsTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $RecentsTable,
      RecentRow,
      $$RecentsTableFilterComposer,
      $$RecentsTableOrderingComposer,
      $$RecentsTableAnnotationComposer,
      $$RecentsTableCreateCompanionBuilder,
      $$RecentsTableUpdateCompanionBuilder,
      (RecentRow, BaseReferences<_$KelolaDatabase, $RecentsTable, RecentRow>),
      RecentRow,
      PrefetchHooks Function()
    >;
typedef $$PinsTableCreateCompanionBuilder =
    PinsCompanion Function({
      Value<int> id,
      required String hostId,
      required String kind,
      required String label,
      required String route,
      required int sortOrder,
    });
typedef $$PinsTableUpdateCompanionBuilder =
    PinsCompanion Function({
      Value<int> id,
      Value<String> hostId,
      Value<String> kind,
      Value<String> label,
      Value<String> route,
      Value<int> sortOrder,
    });

class $$PinsTableFilterComposer extends Composer<_$KelolaDatabase, $PinsTable> {
  $$PinsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PinsTableOrderingComposer
    extends Composer<_$KelolaDatabase, $PinsTable> {
  $$PinsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PinsTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $PinsTable> {
  $$PinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get route =>
      $composableBuilder(column: $table.route, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$PinsTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $PinsTable,
          PinRow,
          $$PinsTableFilterComposer,
          $$PinsTableOrderingComposer,
          $$PinsTableAnnotationComposer,
          $$PinsTableCreateCompanionBuilder,
          $$PinsTableUpdateCompanionBuilder,
          (PinRow, BaseReferences<_$KelolaDatabase, $PinsTable, PinRow>),
          PinRow,
          PrefetchHooks Function()
        > {
  $$PinsTableTableManager(_$KelolaDatabase db, $PinsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PinsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PinsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> hostId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> route = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => PinsCompanion(
                id: id,
                hostId: hostId,
                kind: kind,
                label: label,
                route: route,
                sortOrder: sortOrder,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String hostId,
                required String kind,
                required String label,
                required String route,
                required int sortOrder,
              }) => PinsCompanion.insert(
                id: id,
                hostId: hostId,
                kind: kind,
                label: label,
                route: route,
                sortOrder: sortOrder,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PinsTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $PinsTable,
      PinRow,
      $$PinsTableFilterComposer,
      $$PinsTableOrderingComposer,
      $$PinsTableAnnotationComposer,
      $$PinsTableCreateCompanionBuilder,
      $$PinsTableUpdateCompanionBuilder,
      (PinRow, BaseReferences<_$KelolaDatabase, $PinsTable, PinRow>),
      PinRow,
      PrefetchHooks Function()
    >;
typedef $$AuditRecordsTableCreateCompanionBuilder =
    AuditRecordsCompanion Function({
      required String id,
      required DateTime timestampUtc,
      required String hostId,
      required String hostAlias,
      required String remoteUser,
      Value<String> title,
      required String command,
      required String risk,
      required bool usedSudo,
      Value<int?> exitCode,
      Value<int> durationMs,
      Value<String?> errorSummary,
      required String appVersion,
      Value<int> rowid,
    });
typedef $$AuditRecordsTableUpdateCompanionBuilder =
    AuditRecordsCompanion Function({
      Value<String> id,
      Value<DateTime> timestampUtc,
      Value<String> hostId,
      Value<String> hostAlias,
      Value<String> remoteUser,
      Value<String> title,
      Value<String> command,
      Value<String> risk,
      Value<bool> usedSudo,
      Value<int?> exitCode,
      Value<int> durationMs,
      Value<String?> errorSummary,
      Value<String> appVersion,
      Value<int> rowid,
    });

class $$AuditRecordsTableFilterComposer
    extends Composer<_$KelolaDatabase, $AuditRecordsTable> {
  $$AuditRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestampUtc => $composableBuilder(
    column: $table.timestampUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostAlias => $composableBuilder(
    column: $table.hostAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteUser => $composableBuilder(
    column: $table.remoteUser,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get risk => $composableBuilder(
    column: $table.risk,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get usedSudo => $composableBuilder(
    column: $table.usedSudo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get exitCode => $composableBuilder(
    column: $table.exitCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorSummary => $composableBuilder(
    column: $table.errorSummary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuditRecordsTableOrderingComposer
    extends Composer<_$KelolaDatabase, $AuditRecordsTable> {
  $$AuditRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestampUtc => $composableBuilder(
    column: $table.timestampUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostAlias => $composableBuilder(
    column: $table.hostAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteUser => $composableBuilder(
    column: $table.remoteUser,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get risk => $composableBuilder(
    column: $table.risk,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get usedSudo => $composableBuilder(
    column: $table.usedSudo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get exitCode => $composableBuilder(
    column: $table.exitCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorSummary => $composableBuilder(
    column: $table.errorSummary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuditRecordsTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $AuditRecordsTable> {
  $$AuditRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get timestampUtc => $composableBuilder(
    column: $table.timestampUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get hostAlias =>
      $composableBuilder(column: $table.hostAlias, builder: (column) => column);

  GeneratedColumn<String> get remoteUser => $composableBuilder(
    column: $table.remoteUser,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get command =>
      $composableBuilder(column: $table.command, builder: (column) => column);

  GeneratedColumn<String> get risk =>
      $composableBuilder(column: $table.risk, builder: (column) => column);

  GeneratedColumn<bool> get usedSudo =>
      $composableBuilder(column: $table.usedSudo, builder: (column) => column);

  GeneratedColumn<int> get exitCode =>
      $composableBuilder(column: $table.exitCode, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorSummary => $composableBuilder(
    column: $table.errorSummary,
    builder: (column) => column,
  );

  GeneratedColumn<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => column,
  );
}

class $$AuditRecordsTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $AuditRecordsTable,
          AuditRow,
          $$AuditRecordsTableFilterComposer,
          $$AuditRecordsTableOrderingComposer,
          $$AuditRecordsTableAnnotationComposer,
          $$AuditRecordsTableCreateCompanionBuilder,
          $$AuditRecordsTableUpdateCompanionBuilder,
          (
            AuditRow,
            BaseReferences<_$KelolaDatabase, $AuditRecordsTable, AuditRow>,
          ),
          AuditRow,
          PrefetchHooks Function()
        > {
  $$AuditRecordsTableTableManager(_$KelolaDatabase db, $AuditRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> timestampUtc = const Value.absent(),
                Value<String> hostId = const Value.absent(),
                Value<String> hostAlias = const Value.absent(),
                Value<String> remoteUser = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> command = const Value.absent(),
                Value<String> risk = const Value.absent(),
                Value<bool> usedSudo = const Value.absent(),
                Value<int?> exitCode = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String?> errorSummary = const Value.absent(),
                Value<String> appVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AuditRecordsCompanion(
                id: id,
                timestampUtc: timestampUtc,
                hostId: hostId,
                hostAlias: hostAlias,
                remoteUser: remoteUser,
                title: title,
                command: command,
                risk: risk,
                usedSudo: usedSudo,
                exitCode: exitCode,
                durationMs: durationMs,
                errorSummary: errorSummary,
                appVersion: appVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime timestampUtc,
                required String hostId,
                required String hostAlias,
                required String remoteUser,
                Value<String> title = const Value.absent(),
                required String command,
                required String risk,
                required bool usedSudo,
                Value<int?> exitCode = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String?> errorSummary = const Value.absent(),
                required String appVersion,
                Value<int> rowid = const Value.absent(),
              }) => AuditRecordsCompanion.insert(
                id: id,
                timestampUtc: timestampUtc,
                hostId: hostId,
                hostAlias: hostAlias,
                remoteUser: remoteUser,
                title: title,
                command: command,
                risk: risk,
                usedSudo: usedSudo,
                exitCode: exitCode,
                durationMs: durationMs,
                errorSummary: errorSummary,
                appVersion: appVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuditRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $AuditRecordsTable,
      AuditRow,
      $$AuditRecordsTableFilterComposer,
      $$AuditRecordsTableOrderingComposer,
      $$AuditRecordsTableAnnotationComposer,
      $$AuditRecordsTableCreateCompanionBuilder,
      $$AuditRecordsTableUpdateCompanionBuilder,
      (
        AuditRow,
        BaseReferences<_$KelolaDatabase, $AuditRecordsTable, AuditRow>,
      ),
      AuditRow,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> id,
      Value<String?> lastHostId,
      Value<String?> publicKeySpkiB64,
      Value<String?> keyBackend,
      Value<bool> widgetEnabled,
      Value<String> llmProvider,
      Value<String?> llmBaseUrl,
      Value<String?> llmApiKey,
      Value<String?> llmModel,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> id,
      Value<String?> lastHostId,
      Value<String?> publicKeySpkiB64,
      Value<String?> keyBackend,
      Value<bool> widgetEnabled,
      Value<String> llmProvider,
      Value<String?> llmBaseUrl,
      Value<String?> llmApiKey,
      Value<String?> llmModel,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$KelolaDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastHostId => $composableBuilder(
    column: $table.lastHostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKeySpkiB64 => $composableBuilder(
    column: $table.publicKeySpkiB64,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyBackend => $composableBuilder(
    column: $table.keyBackend,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get widgetEnabled => $composableBuilder(
    column: $table.widgetEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get llmProvider => $composableBuilder(
    column: $table.llmProvider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get llmBaseUrl => $composableBuilder(
    column: $table.llmBaseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get llmApiKey => $composableBuilder(
    column: $table.llmApiKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get llmModel => $composableBuilder(
    column: $table.llmModel,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$KelolaDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastHostId => $composableBuilder(
    column: $table.lastHostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKeySpkiB64 => $composableBuilder(
    column: $table.publicKeySpkiB64,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyBackend => $composableBuilder(
    column: $table.keyBackend,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get widgetEnabled => $composableBuilder(
    column: $table.widgetEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get llmProvider => $composableBuilder(
    column: $table.llmProvider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get llmBaseUrl => $composableBuilder(
    column: $table.llmBaseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get llmApiKey => $composableBuilder(
    column: $table.llmApiKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get llmModel => $composableBuilder(
    column: $table.llmModel,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get lastHostId => $composableBuilder(
    column: $table.lastHostId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get publicKeySpkiB64 => $composableBuilder(
    column: $table.publicKeySpkiB64,
    builder: (column) => column,
  );

  GeneratedColumn<String> get keyBackend => $composableBuilder(
    column: $table.keyBackend,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get widgetEnabled => $composableBuilder(
    column: $table.widgetEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get llmProvider => $composableBuilder(
    column: $table.llmProvider,
    builder: (column) => column,
  );

  GeneratedColumn<String> get llmBaseUrl => $composableBuilder(
    column: $table.llmBaseUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get llmApiKey =>
      $composableBuilder(column: $table.llmApiKey, builder: (column) => column);

  GeneratedColumn<String> get llmModel =>
      $composableBuilder(column: $table.llmModel, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $AppSettingsTable,
          AppSettingsRow,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSettingsRow,
            BaseReferences<_$KelolaDatabase, $AppSettingsTable, AppSettingsRow>,
          ),
          AppSettingsRow,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$KelolaDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> lastHostId = const Value.absent(),
                Value<String?> publicKeySpkiB64 = const Value.absent(),
                Value<String?> keyBackend = const Value.absent(),
                Value<bool> widgetEnabled = const Value.absent(),
                Value<String> llmProvider = const Value.absent(),
                Value<String?> llmBaseUrl = const Value.absent(),
                Value<String?> llmApiKey = const Value.absent(),
                Value<String?> llmModel = const Value.absent(),
              }) => AppSettingsCompanion(
                id: id,
                lastHostId: lastHostId,
                publicKeySpkiB64: publicKeySpkiB64,
                keyBackend: keyBackend,
                widgetEnabled: widgetEnabled,
                llmProvider: llmProvider,
                llmBaseUrl: llmBaseUrl,
                llmApiKey: llmApiKey,
                llmModel: llmModel,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> lastHostId = const Value.absent(),
                Value<String?> publicKeySpkiB64 = const Value.absent(),
                Value<String?> keyBackend = const Value.absent(),
                Value<bool> widgetEnabled = const Value.absent(),
                Value<String> llmProvider = const Value.absent(),
                Value<String?> llmBaseUrl = const Value.absent(),
                Value<String?> llmApiKey = const Value.absent(),
                Value<String?> llmModel = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                id: id,
                lastHostId: lastHostId,
                publicKeySpkiB64: publicKeySpkiB64,
                keyBackend: keyBackend,
                widgetEnabled: widgetEnabled,
                llmProvider: llmProvider,
                llmBaseUrl: llmBaseUrl,
                llmApiKey: llmApiKey,
                llmModel: llmModel,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $AppSettingsTable,
      AppSettingsRow,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSettingsRow,
        BaseReferences<_$KelolaDatabase, $AppSettingsTable, AppSettingsRow>,
      ),
      AppSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$SearchIndexCacheTableCreateCompanionBuilder =
    SearchIndexCacheCompanion Function({
      required String hostId,
      required String kind,
      required String name,
      required DateTime indexedAt,
      Value<int> rowid,
    });
typedef $$SearchIndexCacheTableUpdateCompanionBuilder =
    SearchIndexCacheCompanion Function({
      Value<String> hostId,
      Value<String> kind,
      Value<String> name,
      Value<DateTime> indexedAt,
      Value<int> rowid,
    });

class $$SearchIndexCacheTableFilterComposer
    extends Composer<_$KelolaDatabase, $SearchIndexCacheTable> {
  $$SearchIndexCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get indexedAt => $composableBuilder(
    column: $table.indexedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SearchIndexCacheTableOrderingComposer
    extends Composer<_$KelolaDatabase, $SearchIndexCacheTable> {
  $$SearchIndexCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get indexedAt => $composableBuilder(
    column: $table.indexedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SearchIndexCacheTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $SearchIndexCacheTable> {
  $$SearchIndexCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get indexedAt =>
      $composableBuilder(column: $table.indexedAt, builder: (column) => column);
}

class $$SearchIndexCacheTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $SearchIndexCacheTable,
          SearchIndexRow,
          $$SearchIndexCacheTableFilterComposer,
          $$SearchIndexCacheTableOrderingComposer,
          $$SearchIndexCacheTableAnnotationComposer,
          $$SearchIndexCacheTableCreateCompanionBuilder,
          $$SearchIndexCacheTableUpdateCompanionBuilder,
          (
            SearchIndexRow,
            BaseReferences<
              _$KelolaDatabase,
              $SearchIndexCacheTable,
              SearchIndexRow
            >,
          ),
          SearchIndexRow,
          PrefetchHooks Function()
        > {
  $$SearchIndexCacheTableTableManager(
    _$KelolaDatabase db,
    $SearchIndexCacheTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SearchIndexCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SearchIndexCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SearchIndexCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> hostId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> indexedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SearchIndexCacheCompanion(
                hostId: hostId,
                kind: kind,
                name: name,
                indexedAt: indexedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String hostId,
                required String kind,
                required String name,
                required DateTime indexedAt,
                Value<int> rowid = const Value.absent(),
              }) => SearchIndexCacheCompanion.insert(
                hostId: hostId,
                kind: kind,
                name: name,
                indexedAt: indexedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SearchIndexCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $SearchIndexCacheTable,
      SearchIndexRow,
      $$SearchIndexCacheTableFilterComposer,
      $$SearchIndexCacheTableOrderingComposer,
      $$SearchIndexCacheTableAnnotationComposer,
      $$SearchIndexCacheTableCreateCompanionBuilder,
      $$SearchIndexCacheTableUpdateCompanionBuilder,
      (
        SearchIndexRow,
        BaseReferences<
          _$KelolaDatabase,
          $SearchIndexCacheTable,
          SearchIndexRow
        >,
      ),
      SearchIndexRow,
      PrefetchHooks Function()
    >;
typedef $$SnippetsTableCreateCompanionBuilder =
    SnippetsCompanion Function({
      required String id,
      required String name,
      required String template,
      Value<bool> starter,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SnippetsTableUpdateCompanionBuilder =
    SnippetsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> template,
      Value<bool> starter,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SnippetsTableFilterComposer
    extends Composer<_$KelolaDatabase, $SnippetsTable> {
  $$SnippetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get template => $composableBuilder(
    column: $table.template,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get starter => $composableBuilder(
    column: $table.starter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SnippetsTableOrderingComposer
    extends Composer<_$KelolaDatabase, $SnippetsTable> {
  $$SnippetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get template => $composableBuilder(
    column: $table.template,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get starter => $composableBuilder(
    column: $table.starter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SnippetsTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $SnippetsTable> {
  $$SnippetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get template =>
      $composableBuilder(column: $table.template, builder: (column) => column);

  GeneratedColumn<bool> get starter =>
      $composableBuilder(column: $table.starter, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SnippetsTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $SnippetsTable,
          SnippetRow,
          $$SnippetsTableFilterComposer,
          $$SnippetsTableOrderingComposer,
          $$SnippetsTableAnnotationComposer,
          $$SnippetsTableCreateCompanionBuilder,
          $$SnippetsTableUpdateCompanionBuilder,
          (
            SnippetRow,
            BaseReferences<_$KelolaDatabase, $SnippetsTable, SnippetRow>,
          ),
          SnippetRow,
          PrefetchHooks Function()
        > {
  $$SnippetsTableTableManager(_$KelolaDatabase db, $SnippetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SnippetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SnippetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SnippetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> template = const Value.absent(),
                Value<bool> starter = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnippetsCompanion(
                id: id,
                name: name,
                template: template,
                starter: starter,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String template,
                Value<bool> starter = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SnippetsCompanion.insert(
                id: id,
                name: name,
                template: template,
                starter: starter,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SnippetsTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $SnippetsTable,
      SnippetRow,
      $$SnippetsTableFilterComposer,
      $$SnippetsTableOrderingComposer,
      $$SnippetsTableAnnotationComposer,
      $$SnippetsTableCreateCompanionBuilder,
      $$SnippetsTableUpdateCompanionBuilder,
      (
        SnippetRow,
        BaseReferences<_$KelolaDatabase, $SnippetsTable, SnippetRow>,
      ),
      SnippetRow,
      PrefetchHooks Function()
    >;
typedef $$HostTagsTableCreateCompanionBuilder =
    HostTagsCompanion Function({
      required String hostId,
      required String tag,
      Value<int> rowid,
    });
typedef $$HostTagsTableUpdateCompanionBuilder =
    HostTagsCompanion Function({
      Value<String> hostId,
      Value<String> tag,
      Value<int> rowid,
    });

class $$HostTagsTableFilterComposer
    extends Composer<_$KelolaDatabase, $HostTagsTable> {
  $$HostTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HostTagsTableOrderingComposer
    extends Composer<_$KelolaDatabase, $HostTagsTable> {
  $$HostTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HostTagsTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $HostTagsTable> {
  $$HostTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);
}

class $$HostTagsTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $HostTagsTable,
          HostTagRow,
          $$HostTagsTableFilterComposer,
          $$HostTagsTableOrderingComposer,
          $$HostTagsTableAnnotationComposer,
          $$HostTagsTableCreateCompanionBuilder,
          $$HostTagsTableUpdateCompanionBuilder,
          (
            HostTagRow,
            BaseReferences<_$KelolaDatabase, $HostTagsTable, HostTagRow>,
          ),
          HostTagRow,
          PrefetchHooks Function()
        > {
  $$HostTagsTableTableManager(_$KelolaDatabase db, $HostTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HostTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HostTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HostTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> hostId = const Value.absent(),
                Value<String> tag = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HostTagsCompanion(hostId: hostId, tag: tag, rowid: rowid),
          createCompanionCallback:
              ({
                required String hostId,
                required String tag,
                Value<int> rowid = const Value.absent(),
              }) => HostTagsCompanion.insert(
                hostId: hostId,
                tag: tag,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HostTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $HostTagsTable,
      HostTagRow,
      $$HostTagsTableFilterComposer,
      $$HostTagsTableOrderingComposer,
      $$HostTagsTableAnnotationComposer,
      $$HostTagsTableCreateCompanionBuilder,
      $$HostTagsTableUpdateCompanionBuilder,
      (
        HostTagRow,
        BaseReferences<_$KelolaDatabase, $HostTagsTable, HostTagRow>,
      ),
      HostTagRow,
      PrefetchHooks Function()
    >;
typedef $$FleetCacheTableCreateCompanionBuilder =
    FleetCacheCompanion Function({
      required String hostId,
      required bool reachable,
      required double load1,
      required int diskRootPercent,
      required int failedUnitCount,
      required int pendingUpdates,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$FleetCacheTableUpdateCompanionBuilder =
    FleetCacheCompanion Function({
      Value<String> hostId,
      Value<bool> reachable,
      Value<double> load1,
      Value<int> diskRootPercent,
      Value<int> failedUnitCount,
      Value<int> pendingUpdates,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$FleetCacheTableFilterComposer
    extends Composer<_$KelolaDatabase, $FleetCacheTable> {
  $$FleetCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reachable => $composableBuilder(
    column: $table.reachable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get load1 => $composableBuilder(
    column: $table.load1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get diskRootPercent => $composableBuilder(
    column: $table.diskRootPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failedUnitCount => $composableBuilder(
    column: $table.failedUnitCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pendingUpdates => $composableBuilder(
    column: $table.pendingUpdates,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FleetCacheTableOrderingComposer
    extends Composer<_$KelolaDatabase, $FleetCacheTable> {
  $$FleetCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get hostId => $composableBuilder(
    column: $table.hostId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reachable => $composableBuilder(
    column: $table.reachable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get load1 => $composableBuilder(
    column: $table.load1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get diskRootPercent => $composableBuilder(
    column: $table.diskRootPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failedUnitCount => $composableBuilder(
    column: $table.failedUnitCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pendingUpdates => $composableBuilder(
    column: $table.pendingUpdates,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FleetCacheTableAnnotationComposer
    extends Composer<_$KelolaDatabase, $FleetCacheTable> {
  $$FleetCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get hostId =>
      $composableBuilder(column: $table.hostId, builder: (column) => column);

  GeneratedColumn<bool> get reachable =>
      $composableBuilder(column: $table.reachable, builder: (column) => column);

  GeneratedColumn<double> get load1 =>
      $composableBuilder(column: $table.load1, builder: (column) => column);

  GeneratedColumn<int> get diskRootPercent => $composableBuilder(
    column: $table.diskRootPercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get failedUnitCount => $composableBuilder(
    column: $table.failedUnitCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pendingUpdates => $composableBuilder(
    column: $table.pendingUpdates,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$FleetCacheTableTableManager
    extends
        RootTableManager<
          _$KelolaDatabase,
          $FleetCacheTable,
          FleetCacheRow,
          $$FleetCacheTableFilterComposer,
          $$FleetCacheTableOrderingComposer,
          $$FleetCacheTableAnnotationComposer,
          $$FleetCacheTableCreateCompanionBuilder,
          $$FleetCacheTableUpdateCompanionBuilder,
          (
            FleetCacheRow,
            BaseReferences<_$KelolaDatabase, $FleetCacheTable, FleetCacheRow>,
          ),
          FleetCacheRow,
          PrefetchHooks Function()
        > {
  $$FleetCacheTableTableManager(_$KelolaDatabase db, $FleetCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FleetCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FleetCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FleetCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> hostId = const Value.absent(),
                Value<bool> reachable = const Value.absent(),
                Value<double> load1 = const Value.absent(),
                Value<int> diskRootPercent = const Value.absent(),
                Value<int> failedUnitCount = const Value.absent(),
                Value<int> pendingUpdates = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FleetCacheCompanion(
                hostId: hostId,
                reachable: reachable,
                load1: load1,
                diskRootPercent: diskRootPercent,
                failedUnitCount: failedUnitCount,
                pendingUpdates: pendingUpdates,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String hostId,
                required bool reachable,
                required double load1,
                required int diskRootPercent,
                required int failedUnitCount,
                required int pendingUpdates,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => FleetCacheCompanion.insert(
                hostId: hostId,
                reachable: reachable,
                load1: load1,
                diskRootPercent: diskRootPercent,
                failedUnitCount: failedUnitCount,
                pendingUpdates: pendingUpdates,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FleetCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$KelolaDatabase,
      $FleetCacheTable,
      FleetCacheRow,
      $$FleetCacheTableFilterComposer,
      $$FleetCacheTableOrderingComposer,
      $$FleetCacheTableAnnotationComposer,
      $$FleetCacheTableCreateCompanionBuilder,
      $$FleetCacheTableUpdateCompanionBuilder,
      (
        FleetCacheRow,
        BaseReferences<_$KelolaDatabase, $FleetCacheTable, FleetCacheRow>,
      ),
      FleetCacheRow,
      PrefetchHooks Function()
    >;

class $KelolaDatabaseManager {
  final _$KelolaDatabase _db;
  $KelolaDatabaseManager(this._db);
  $$HostsTableTableManager get hosts =>
      $$HostsTableTableManager(_db, _db.hosts);
  $$HostKeysTableTableManager get hostKeys =>
      $$HostKeysTableTableManager(_db, _db.hostKeys);
  $$CachedFactsTableTableManager get cachedFacts =>
      $$CachedFactsTableTableManager(_db, _db.cachedFacts);
  $$RecentsTableTableManager get recents =>
      $$RecentsTableTableManager(_db, _db.recents);
  $$PinsTableTableManager get pins => $$PinsTableTableManager(_db, _db.pins);
  $$AuditRecordsTableTableManager get auditRecords =>
      $$AuditRecordsTableTableManager(_db, _db.auditRecords);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$SearchIndexCacheTableTableManager get searchIndexCache =>
      $$SearchIndexCacheTableTableManager(_db, _db.searchIndexCache);
  $$SnippetsTableTableManager get snippets =>
      $$SnippetsTableTableManager(_db, _db.snippets);
  $$HostTagsTableTableManager get hostTags =>
      $$HostTagsTableTableManager(_db, _db.hostTags);
  $$FleetCacheTableTableManager get fleetCache =>
      $$FleetCacheTableTableManager(_db, _db.fleetCache);
}
