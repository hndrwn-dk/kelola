import 'package:kelola/domain/containers/container_row.dart';

const sshFrontingImageTokens = <String>{
  'traefik',
  'caddy',
  'nginx',
  'haproxy',
  'envoy',
  'cloudflared',
  'cloudflare',
  'tailscale',
  'wireguard',
  'gluetun',
  'openssh',
  'dropbear',
  'wg-easy',
  'swag',
  'nginx-proxy',
  'nginxproxymanager',
};

bool isSshFrontingContainer(ContainerRow row, {int sshPort = 22}) {
  final image = row.image.toLowerCase();
  final name = row.names.toLowerCase();
  for (final token in sshFrontingImageTokens) {
    if (image.contains(token) || name.contains(token)) {
      return true;
    }
  }
  if (name.contains('bastion') || name.contains('ssh')) {
    return true;
  }
  return _mentionsPort('${row.publishedPorts} ${row.ports}', sshPort);
}

bool isLockoutContainerAction(
  String verb,
  ContainerRow row, {
  int sshPort = 22,
}) {
  if (verb != 'stop' && verb != 'remove') {
    return false;
  }
  return isSshFrontingContainer(row, sshPort: sshPort);
}

bool _mentionsPort(String blob, int port) {
  final p = '$port';
  for (final chunk in blob.split(RegExp(r'[, ]+'))) {
    if (chunk.isEmpty) {
      continue;
    }
    for (final m in RegExp(r'\d+').allMatches(chunk)) {
      if (m.group(0) == p) {
        return true;
      }
    }
  }
  return false;
}
