import 'package:kelola/data/hosts/coreos_ack_store.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/coreos_node.dart';

/// True when [facts] say OpenShift/OKD node and [hostId] has not
/// acknowledged the first-connect notice. The ack store is only opened for
/// such nodes, so ordinary hosts (and widget tests) never wait on it. An
/// unreadable store blocks: skipping a node is the safe failure.
Future<bool> coreOsNoticeBlocks(
  HostFacts facts,
  String hostId,
  Future<CoreOsAckStore> Function()? acks,
) async {
  if (!facts.isCoreOsNode) {
    return false;
  }
  if (acks == null) {
    return true;
  }
  try {
    final store = await acks();
    return coreOsNoticePending(
      facts,
      acknowledged: await store.isAcknowledged(hostId),
    );
  } catch (_) {
    return true;
  }
}
