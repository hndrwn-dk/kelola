import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';

String tunnelTargetMeta(TunnelTarget target) {
  switch (target.kind) {
    case TunnelKind.local:
      return '${target.scheme.value}://${target.remoteHost}:${target.remotePort}${target.path}';
    case TunnelKind.dynamic:
      return 'socks5';
    case TunnelKind.remote:
      return 'remote · ${target.remoteHost}:${target.remotePort}';
    case TunnelKind.kubectl:
      final ns = target.path.trim();
      final prefix = ns.isEmpty ? 'default' : ns;
      return 'kubectl · $prefix/${target.remoteHost}:${target.remotePort}';
  }
}

bool tunnelAllowsBrowser(TunnelTarget target) {
  return target.kind == TunnelKind.local || target.kind == TunnelKind.kubectl;
}

String tunnelStopBody(ActiveTunnel tunnel) {
  switch (tunnel.target.kind) {
    case TunnelKind.dynamic:
      return 'Closes the SOCKS5 listener on 127.0.0.1:${tunnel.localPort}.';
    case TunnelKind.remote:
      return 'Closes the remote listen on the host. '
          'The destination keeps running.';
    case TunnelKind.kubectl:
      return 'Stops host kubectl port-forward and the local forward '
          'on 127.0.0.1:${tunnel.localPort}.';
    case TunnelKind.local:
      return 'Closes the local forward on 127.0.0.1:${tunnel.localPort}. '
          'The remote service keeps running.';
  }
}
