import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:kelola/data/db/tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Hosts, HostKeys, CachedFacts, Recents, Pins, AuditRecords, AppSettings],
)
class KelolaDatabase extends _$KelolaDatabase {
  KelolaDatabase() : super(driftDatabase(name: 'kelola'));

  KelolaDatabase.memory() : super(NativeDatabase.memory());

  KelolaDatabase.connect(super.e);

  @override
  int get schemaVersion => 1;
}
