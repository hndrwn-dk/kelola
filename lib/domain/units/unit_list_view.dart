import 'package:kelola/domain/units/service_unit.dart';

enum UnitListFilter { failed, running, enabled, all }

class UnitListCounts {
  const UnitListCounts({
    required this.failed,
    required this.running,
    required this.enabled,
    required this.all,
  });

  final int failed;
  final int running;
  final int enabled;
  final int all;

  factory UnitListCounts.from(List<ServiceUnit> units) {
    var failed = 0;
    var running = 0;
    var enabled = 0;
    for (final u in units) {
      if (u.isFailed) {
        failed++;
      } else if (u.isActive) {
        running++;
      }
      if (_isEnabled(u)) {
        enabled++;
      }
    }
    return UnitListCounts(
      failed: failed,
      running: running,
      enabled: enabled,
      all: units.length,
    );
  }
}

class UnitListView {
  const UnitListView({
    required this.failed,
    required this.running,
    required this.other,
  });

  final List<ServiceUnit> failed;
  final List<ServiceUnit> running;
  final List<ServiceUnit> other;

  bool get isEmpty => failed.isEmpty && running.isEmpty && other.isEmpty;

  bool get showRunningSlab =>
      running.isNotEmpty && (failed.isNotEmpty || other.isNotEmpty);

  bool get showOtherSlab => other.isNotEmpty && (failed.isNotEmpty || running.isNotEmpty);

  static UnitListView build(
    List<ServiceUnit> units,
    UnitListFilter filter, {
    String query = '',
  }) {
    var list = units;
    switch (filter) {
      case UnitListFilter.failed:
        list = units.where((u) => u.isFailed).toList();
      case UnitListFilter.running:
        list = units.where((u) => u.isActive && !u.isFailed).toList();
      case UnitListFilter.enabled:
        list = units.where(_isEnabled).toList();
      case UnitListFilter.all:
        list = units;
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (u) =>
                u.name.toLowerCase().contains(q) ||
                u.description.toLowerCase().contains(q),
          )
          .toList();
    }
    return UnitListView(
      failed: list.where((u) => u.isFailed).toList(),
      running: list.where((u) => u.isActive && !u.isFailed).toList(),
      other: list.where((u) => !u.isFailed && !u.isActive).toList(),
    );
  }
}

bool _isEnabled(ServiceUnit unit) =>
    (unit.unitFileState ?? '').toLowerCase() == 'enabled';

UnitListFilter defaultUnitListFilter(List<ServiceUnit> units) {
  return units.any((u) => u.isFailed)
      ? UnitListFilter.failed
      : UnitListFilter.all;
}

String unitListKicker(UnitListCounts counts) =>
    '${counts.all} UNITS · ${counts.failed} FAILED';

String unitListChipLabel(UnitListFilter filter, UnitListCounts counts) {
  return switch (filter) {
    UnitListFilter.failed => 'Failed ${counts.failed}',
    UnitListFilter.running => 'Running ${counts.running}',
    UnitListFilter.enabled => 'Enabled ${counts.enabled}',
    UnitListFilter.all => 'All ${counts.all}',
  };
}

String unitListEmptyCopy(
  UnitListFilter filter, {
  required int activeCount,
  String query = '',
}) {
  if (query.trim().isNotEmpty) {
    return 'No units match.';
  }
  return switch (filter) {
    UnitListFilter.failed => 'No failed units · $activeCount active',
    UnitListFilter.running => 'No running units.',
    UnitListFilter.enabled => 'No enabled units.',
    UnitListFilter.all => 'No units match.',
  };
}

String unitListMeta(ServiceUnit unit) {
  final bits = <String>[unit.active];
  if (unit.sub.isNotEmpty && unit.sub != unit.active) {
    bits.add(unit.sub);
  }
  return bits.join(' · ');
}
