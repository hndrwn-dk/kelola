import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';

class InventorySearch {
  const InventorySearch();

  List<Host> query(List<Host> hosts, String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) {
      return hosts;
    }
    return hosts.where((h) {
      return h.alias.toLowerCase().contains(q) ||
          h.address.toLowerCase().contains(q) ||
          (h.note?.toLowerCase().contains(q) ?? false) ||
          h.username.toLowerCase().contains(q);
    }).toList();
  }
}

int attentionRank(Host host) {
  switch (host.attention) {
    case HostAttention.failedUnits:
      return 0;
    case HostAttention.diskHigh:
      return 1;
    case HostAttention.unreachable:
      return 2;
    case HostAttention.unknown:
      return 3;
    case HostAttention.healthy:
      return 4;
  }
}

List<Host> sortByAttention(List<Host> hosts) {
  final copy = [...hosts];
  copy.sort((a, b) {
    final r = attentionRank(a).compareTo(attentionRank(b));
    if (r != 0) {
      return r;
    }
    return a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
  });
  return copy;
}
