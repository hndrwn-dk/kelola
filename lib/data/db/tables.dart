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
  IntColumn get failedUnitCount => integer().nullable()();
  IntColumn get diskRootPercent => integer().nullable()();
  DateTimeColumn get attentionAt => dateTime().nullable()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get sudoNeedsPassword =>
      boolean().withDefault(const Constant(false))();

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
  TextColumn get title => text().withDefault(const Constant(''))();
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
  BoolColumn get widgetEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get llmProvider =>
      text().withDefault(const Constant('none'))();
  /// Legacy shared fields — no longer written; kept for migration from < 11.
  TextColumn get llmBaseUrl => text().nullable()();
  TextColumn get llmApiKey => text().nullable()();
  TextColumn get llmModel => text().nullable()();
  TextColumn get llmOllamaBaseUrl => text().nullable()();
  TextColumn get llmOllamaModel => text().nullable()();
  TextColumn get llmOpenaiBaseUrl => text().nullable()();
  TextColumn get llmOpenaiApiKey => text().nullable()();
  TextColumn get llmOpenaiModel => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SearchIndexRow')
class SearchIndexCache extends Table {
  @override
  String get tableName => 'search_index';

  TextColumn get hostId => text().references(Hosts, #id)();
  TextColumn get kind => text()();
  TextColumn get name => text()();
  DateTimeColumn get indexedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {hostId, kind, name};
}

@DataClassName('SnippetRow')
class Snippets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get template => text()();
  BoolColumn get starter => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('HostTagRow')
class HostTags extends Table {
  TextColumn get hostId => text().references(Hosts, #id)();
  TextColumn get tag => text()();

  @override
  Set<Column<Object>> get primaryKey => {hostId, tag};
}

@DataClassName('FleetCacheRow')
class FleetCache extends Table {
  TextColumn get hostId => text().references(Hosts, #id)();
  BoolColumn get reachable => boolean()();
  RealColumn get load1 => real()();
  IntColumn get diskRootPercent => integer()();
  IntColumn get failedUnitCount => integer()();
  IntColumn get pendingUpdates => integer()();
  DateTimeColumn get fetchedAt => dateTime()();
  IntColumn get nprocCores => integer().nullable()();
  IntColumn get memPercent => integer().withDefault(const Constant(0))();
  TextColumn get highDiskJson => text().withDefault(const Constant('[]'))();
  IntColumn get securityUpdates => integer().withDefault(const Constant(0))();
  IntColumn get containersDown => integer().withDefault(const Constant(0))();
  IntColumn get containersUnhealthy =>
      integer().withDefault(const Constant(0))();
  IntColumn get uptimeSeconds => integer().withDefault(const Constant(0))();
  BoolColumn get rebootRequired =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {hostId};
}
