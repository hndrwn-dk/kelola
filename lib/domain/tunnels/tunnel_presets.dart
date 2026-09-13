import 'package:kelola/domain/tunnels/tunnel_target.dart';

enum TunnelPreset {
  cockpit,
  portainer,
  grafana,
  prometheus,
  custom,
}

class TunnelPresets {
  const TunnelPresets._();

  static TunnelTarget apply({
    required TunnelPreset preset,
    required String id,
    required String hostId,
    String label = '',
    String remoteHost = '',
    int remotePort = 0,
    TunnelScheme scheme = TunnelScheme.http,
    String path = '',
  }) {
    switch (preset) {
      case TunnelPreset.cockpit:
        return TunnelTarget(
          id: id,
          hostId: hostId,
          label: 'Cockpit',
          remoteHost: remoteHost,
          remotePort: 9090,
          scheme: TunnelScheme.https,
          path: '/',
        );
      case TunnelPreset.portainer:
        return TunnelTarget(
          id: id,
          hostId: hostId,
          label: 'Portainer',
          remoteHost: remoteHost,
          remotePort: 9443,
          scheme: TunnelScheme.https,
          path: '/',
        );
      case TunnelPreset.grafana:
        return TunnelTarget(
          id: id,
          hostId: hostId,
          label: 'Grafana',
          remoteHost: remoteHost,
          remotePort: 3000,
          scheme: TunnelScheme.http,
          path: '/',
        );
      case TunnelPreset.prometheus:
        return TunnelTarget(
          id: id,
          hostId: hostId,
          label: 'Prometheus',
          remoteHost: remoteHost,
          remotePort: 9090,
          scheme: TunnelScheme.http,
          path: '/',
        );
      case TunnelPreset.custom:
        return TunnelTarget(
          id: id,
          hostId: hostId,
          label: label,
          remoteHost: remoteHost,
          remotePort: remotePort,
          scheme: scheme,
          path: path,
        );
    }
  }
}
