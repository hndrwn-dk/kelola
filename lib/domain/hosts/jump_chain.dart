import 'package:kelola/domain/hosts/host.dart';

/// Longest ProxyJump chain Kelola will walk. Dest plus this many hops.
const kMaxJumpHops = 8;

enum JumpChainKind { ok, cycle, missing, tooLong }

class JumpChain {
  const JumpChain._(this.kind, this.hops);

  final JumpChainKind kind;
  final List<Host> hops;

  bool get isOk => kind == JumpChainKind.ok;

  String? get viaLabel {
    if (hops.isEmpty) {
      return null;
    }
    return 'via ${hops.map((h) => h.alias).join(' · ')}';
  }
}

/// Walks [host.jumpHostId] until a direct host. [hops] are outermost first.
JumpChain resolveJumpChain(Host host, Map<String, Host> byId) {
  if (host.jumpHostId == null) {
    return const JumpChain._(JumpChainKind.ok, []);
  }
  final immediateFirst = <Host>[];
  final seen = {host.id};
  var id = host.jumpHostId;
  while (id != null) {
    if (!seen.add(id)) {
      return JumpChain._(JumpChainKind.cycle, immediateFirst);
    }
    if (immediateFirst.length >= kMaxJumpHops) {
      return JumpChain._(JumpChainKind.tooLong, immediateFirst);
    }
    final hop = byId[id];
    if (hop == null) {
      return JumpChain._(JumpChainKind.missing, immediateFirst);
    }
    immediateFirst.add(hop);
    id = hop.jumpHostId;
  }
  return JumpChain._(JumpChainKind.ok, immediateFirst.reversed.toList());
}

JumpChain resolveProposedJump(
  Host host,
  String? jumpHostId,
  Map<String, Host> byId,
) {
  final proposed = host.withJumpHostId(jumpHostId);
  return resolveJumpChain(proposed, {...byId, host.id: proposed});
}

bool wouldCycle(String hostId, String? jumpId, Map<String, Host> byId) {
  if (jumpId == null) {
    return false;
  }
  if (jumpId == hostId) {
    return true;
  }
  final host = byId[hostId];
  if (host == null) {
    return true;
  }
  return resolveProposedJump(host, jumpId, byId).kind == JumpChainKind.cycle;
}

String? jumpViaLabel(Host host, Map<String, Host> byId) {
  final chain = resolveJumpChain(host, byId);
  if (!chain.isOk) {
    return null;
  }
  return chain.viaLabel;
}

String appendVia(String base, String? via) {
  if (via == null || via.isEmpty) {
    return base;
  }
  return '$base · $via';
}
