import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';

/// Ports `kubectl port-forward` can carry (TCP only). ExternalName
/// Services have no backing pods to forward to.
List<K8sServicePort> forwardablePorts(K8sService service) {
  if (service.type == 'ExternalName') {
    return const [];
  }
  return [
    for (final p in service.portList)
      if (p.protocol.toUpperCase() == 'TCP') p,
  ];
}

/// Tunnel target for forwarding [port] of [service] through the host's
/// kubectl (M5 `TunnelKind.kubectl`: resource in `remoteHost`, namespace in
/// `path`). Reuses a saved target for the same resource, namespace and
/// port so repeated taps do not pile up duplicates.
TunnelTarget serviceForwardTarget({
  required String hostId,
  required K8sService service,
  required K8sServicePort port,
  required List<TunnelTarget> saved,
  required String Function() newId,
}) {
  final resource = 'svc/${service.name}';
  for (final t in saved) {
    if (t.hostId == hostId &&
        t.kind == TunnelKind.kubectl &&
        t.remoteHost == resource &&
        t.path == service.namespace &&
        t.remotePort == port.port) {
      return t;
    }
  }
  return TunnelTarget(
    id: newId(),
    hostId: hostId,
    label: '${service.name}:${port.port}',
    remoteHost: resource,
    remotePort: port.port,
    scheme: TunnelScheme.http,
    path: service.namespace,
    kind: TunnelKind.kubectl,
  );
}
