import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';

/// Lightweight inventory ping: cached facts if present, otherwise
/// [HostFactsProbe], then [DashboardProbe] to fill attention buckets.
/// Does not write attention — the caller does that after the 10s timeout.
Future<DashboardPing> probeInventoryHost({
  required SshSessionPool pool,
  required HostRepository repo,
  required Host host,
}) async {
  var facts = await repo.facts(host.id) ?? HostFacts.undiscovered;
  if (facts.osId.isEmpty) {
    facts = await pool.execute(
      host,
      const HostFactsProbe(),
      onUnknownHostKey: _rejectUnknownKey,
    );
    await repo.saveFacts(host.id, facts);
  }
  final dash = await pool.execute(
    host,
    const DashboardProbe(),
    facts: facts,
    onUnknownHostKey: _rejectUnknownKey,
  );
  final attention = switch (dash.attention) {
    HostAttentionFromSnapshot.failedUnits => HostAttention.failedUnits,
    HostAttentionFromSnapshot.diskHigh => HostAttention.diskHigh,
    HostAttentionFromSnapshot.healthy => HostAttention.healthy,
  };
  return DashboardPing(
    attention: attention,
    failedUnitCount: dash.failedUnitCount,
    diskRootPercent: dash.diskRootPercent,
  );
}

Future<void> storeInventoryPing({
  required HostRepository repo,
  required Host host,
  required DashboardPing ping,
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toUtc();
  return repo.updateAttention(
    id: host.id,
    attention: ping.attention,
    lastSeenAt: at,
    failedUnitCount: ping.failedUnitCount,
    diskRootPercent: ping.diskRootPercent,
    attentionAt: at,
  );
}

Future<void> storeInventoryPingFailed({
  required HostRepository repo,
  required Host host,
  DateTime? now,
}) {
  return repo.updateAttention(
    id: host.id,
    attention: HostAttention.unreachable,
    attentionAt: (now ?? DateTime.now()).toUtc(),
  );
}

Future<bool> _rejectUnknownKey(
  String hostId,
  String algorithm,
  String fingerprint,
) async {
  return false;
}

class DashboardPing {
  const DashboardPing({
    required this.attention,
    required this.failedUnitCount,
    required this.diskRootPercent,
  });

  final HostAttention attention;
  final int failedUnitCount;
  final int diskRootPercent;
}
