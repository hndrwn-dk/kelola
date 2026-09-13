import 'package:kelola/domain/tunnels/tunnel_target.dart';

enum TunnelState {
  starting,
  listening,
  idleClosing,
  failed,
  closing,
  closed,
}

class ActiveTunnel {
  const ActiveTunnel({
    required this.id,
    required this.target,
    required this.hostAlias,
    required this.localPort,
    required this.state,
    required this.openedAtUtc,
    required this.openChannels,
    this.closesAtUtc,
    this.errorSummary,
    this.droppedChannels = 0,
  });

  final String id;
  final TunnelTarget target;
  final String hostAlias;
  final int localPort;
  final TunnelState state;
  final DateTime openedAtUtc;
  final int openChannels;
  final DateTime? closesAtUtc;
  final String? errorSummary;
  final int droppedChannels;

  Uri get url {
    final path = target.path;
    return Uri(
      scheme: target.scheme.value,
      host: '127.0.0.1',
      port: localPort,
      path: path.isEmpty ? null : path,
    );
  }
}
