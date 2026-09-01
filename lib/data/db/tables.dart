import 'package:drift/drift.dart';

@DataClassName('HostRow')
class Hosts extends Table {
  TextColumn get id => text()();
  TextColumn get alias => text()();
  TextColumn get address => text()();
  IntColumn get port => integer().withDefault(const Constant(22))();
  TextColumn get username => text()();
  TextColumn get keyAlias => text()();
  TextColumn get jumpHostId => text().nullable()();
  BoolColumn get readOnly => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  IntColumn get lastRttMs => integer().nullable()();
  TextColumn get attention => text().withDefault(const Constant('unknown'))();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('HostKeyRow')
class HostKeys extends Table {
  TextColumn get hostId => text().references(Hosts, #id)();
  TextColumn get algorithm => text()();
  TextColumn get fingerprint => text()();
  DateTimeColumn get pinnedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {hostId};
}

@DataClassName('CachedFactsRow')
class CachedFacts extends Table {
  TextColumn get hostId => text().references(Hosts, #id)();
  TextColumn get osId => text()();
  TextColumn get osVersionId => text()();
  TextColumn get prettyName => text().nullable()();
  TextColumn get initSystem => text()();
  IntColumn get systemdVersion => integer().nullable()();
  TextColumn get pkg => text()();
  TextColumn get fw => text()();
  BoolColumn get hasJournald => boolean()();
  BoolColumn get journalReadable => boolean()();
  TextColumn get arch => text()();
  DateTimeColumn get discoveredAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {hostId};
}

@DataClassName('RecentRow')
class Recents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()();
  TextColumn get hostId => text()();
  TextColumn get label => text()();
  DateTimeColumn get viewedAt => dateTime()();
}

@DataClassName('PinRow')
class Pins extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get hostId => text()();
  TextColumn get kind => text()();
  TextColumn get label => text()();
  TextColumn get route => text()();
  IntColumn get sortOrder => integer()();
}

@DataClassName('AuditRow')
class AuditRecords extends Table {
  TextColumn get id => text()();
  DateTimeColumn get timestampUtc => dateTime()();
  TextColumn get hostId => text()();
  TextColumn get hostAlias => text()();
  TextColumn get remoteUser => text()();
  TextColumn get command => text()();
  TextColumn get risk => text()();
  BoolColumn get usedSudo => boolean()();
  IntColumn get exitCode => integer().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get errorSummary => text().nullable()();
  TextColumn get appVersion => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AppSettingsRow')
class AppSettings extends Table {
  IntColumn get id => integer()();
  TextColumn get lastHostId => text().nullable()();
  TextColumn get publicKeySpkiB64 => text().nullable()();
  TextColumn get keyBackend => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
