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
    this.lastSeenAt,
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
  final DateTime? lastSeenAt;

  String get subtitle {
    final bits = <String>['$address:$port'];
    if (readOnly) {
      bits.add('read-only');
    }
    return bits.join(' · ');
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
