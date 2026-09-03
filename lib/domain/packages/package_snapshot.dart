import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/packages/package_commands.dart';

class PackageUpdate {
  const PackageUpdate({
    required this.name,
    this.currentVersion,
    this.candidateVersion,
    this.security = false,
  });

  final String name;
  final String? currentVersion;
  final String? candidateVersion;
  final bool security;

  PackageUpdate copyWith({bool? security}) {
    return PackageUpdate(
      name: name,
      currentVersion: currentVersion,
      candidateVersion: candidateVersion,
      security: security ?? this.security,
    );
  }

  String get versionMeta {
    final cur = currentVersion;
    final cand = candidateVersion;
    if (cur != null && cur.isNotEmpty && cand != null && cand.isNotEmpty) {
      return '$cur → $cand';
    }
    if (cand != null && cand.isNotEmpty) {
      return cand;
    }
    if (cur != null && cur.isNotEmpty) {
      return cur;
    }
    return '';
  }
}

class PackageSnapshot {
  const PackageSnapshot({
    required this.manager,
    required this.updates,
    required this.rebootRequired,
    this.rebootReasons = const [],
  });

  final PackageManager manager;
  final List<PackageUpdate> updates;
  final bool rebootRequired;
  final List<String> rebootReasons;

  bool get securitySupported => PackageCommands.securitySupported(manager);

  int get securityCount => updates.where((u) => u.security).length;
}

enum PackageListFilter { security, all }

class PackageListCounts {
  const PackageListCounts({
    required this.security,
    required this.all,
  });

  final int security;
  final int all;

  factory PackageListCounts.from(PackageSnapshot snapshot) {
    return PackageListCounts(
      security: snapshot.securityCount,
      all: snapshot.updates.length,
    );
  }
}

PackageListFilter defaultPackageFilter(PackageSnapshot snapshot) {
  if (snapshot.securitySupported && snapshot.securityCount > 0) {
    return PackageListFilter.security;
  }
  return PackageListFilter.all;
}

String packageListChipLabel(PackageListFilter filter, PackageListCounts counts) {
  return switch (filter) {
    PackageListFilter.security => 'Security ${counts.security}',
    PackageListFilter.all => 'All ${counts.all}',
  };
}

String packageListEmptyCopy(PackageListFilter filter, {String query = ''}) {
  if (query.trim().isNotEmpty) {
    return 'No packages match.';
  }
  return switch (filter) {
    PackageListFilter.security => 'No security updates.',
    PackageListFilter.all => 'No updates.',
  };
}

String packageApplyAuditTitle({
  required int count,
  required bool securityOnly,
}) {
  if (securityOnly) {
    return 'Applied $count security updates';
  }
  return 'Applied $count updates';
}

List<PackageUpdate> visiblePackageUpdates(
  PackageSnapshot snapshot,
  PackageListFilter filter, {
  String query = '',
}) {
  var list = switch (filter) {
    PackageListFilter.security =>
      snapshot.updates.where((u) => u.security).toList(),
    PackageListFilter.all => snapshot.updates,
  };
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    list = list.where((u) => u.name.toLowerCase().contains(q)).toList();
  }
  return list;
}
