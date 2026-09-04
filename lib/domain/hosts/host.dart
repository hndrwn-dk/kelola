import 'package:kelola/domain/facts/enums.dart';

class Host {
  const Host({
    required this.id,
    required this.alias,
    required this.address,
    required this.port,
    required this.username,
    required this.keyAlias,
    this.jumpHostId,
    this.readOnly = false,
    this.sortOrder = 0,
    this.note,
    this.lastRttMs,
    this.attention = HostAttention.unknown,
    this.failedUnitCount,
    this.diskRootPercent,
    this.attentionAt,
    this.lastSeenAt,
    this.prettyName,
    this.osId,
    this.sudoNeedsPassword = false,
    this.tags = const [],
  });

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
  final HostAttention attention;
  final int? failedUnitCount;
  final int? diskRootPercent;
  final DateTime? attentionAt;
  final DateTime? lastSeenAt;
  final String? prettyName;
  final String? osId;
  final bool sudoNeedsPassword;
  final List<String> tags;

  /// Last dashboard snapshot older than this is labelled stale, never current.
  static const attentionFreshFor = Duration(minutes: 15);

  bool get needsAttention =>
      attention == HostAttention.failedUnits ||
      attention == HostAttention.diskHigh ||
      attention == HostAttention.unreachable;

  /// Never-opened hosts have no [attentionAt] and are not stale cache.
  bool isAttentionStale({DateTime? now}) {
    final at = attentionAt;
    if (at == null) {
      return false;
    }
    final n = (now ?? DateTime.now()).toUtc();
    return n.difference(at.toUtc()) > attentionFreshFor;
  }

  /// Host-list pill. Null until the dashboard has stored a snapshot.
  String? attentionPill({DateTime? now}) {
    if (attentionAt == null) {
      return null;
    }
    final String? base;
    if (failedUnitCount != null && failedUnitCount! > 0) {
      base = '$failedUnitCount failed';
    } else if (diskRootPercent != null && diskRootPercent! >= 90) {
      base = 'disk $diskRootPercent%';
    } else if (attention == HostAttention.healthy) {
      base = readOnly ? 'read-only' : 'healthy';
    } else {
      base = null;
    }
    if (base == null) {
      return null;
    }
    if (isAttentionStale(now: now)) {
      return '$base · ${ageLabel(attentionAt!, now: now)}';
    }
    return base;
  }

  String get endpoint {
    if (port == 22) {
      return address;
    }
    return '$address:$port';
  }

  String get subtitle {
    if (attention == HostAttention.unreachable) {
      final seen = lastSeenAt == null ? 'never' : ageLabel(lastSeenAt!);
      return 'unreachable · last seen $seen';
    }
    final bits = <String>[endpoint];
    if (prettyName != null && prettyName!.isNotEmpty) {
      bits.add(prettyName!);
    }
    if (readOnly) {
      bits.add('read-only');
    }
    return bits.join(' · ');
  }

  static String ageLabel(DateTime t, {DateTime? now}) {
    final d = (now ?? DateTime.now()).toUtc().difference(t.toUtc());
    if (d.inMinutes < 1) {
      return 'just now';
    }
    if (d.inHours < 1) {
      return '${d.inMinutes}m ago';
    }
    if (d.inDays < 1) {
      return '${d.inHours}h ago';
    }
    return '${d.inDays}d ago';
  }
}

class ImportedSshHost {
  const ImportedSshHost({
    required this.alias,
    required this.address,
    required this.port,
    required this.username,
    this.proxyJump,
  });

  final String alias;
  final String address;
  final int port;
  final String username;
  final String? proxyJump;
}
