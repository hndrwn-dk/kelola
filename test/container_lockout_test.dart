import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_lockout.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/probes/container_action_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

ContainerRow _row({
  required String names,
  String image = 'nginx',
  String publishedPorts = '',
  String ports = '',
  String state = 'running',
}) {
  return ContainerRow(
    id: names,
    names: names,
    image: image,
    state: state,
    status: 'Up',
    ports: ports,
    publishedPorts: publishedPorts,
  );
}

void main() {
  test('SSH-fronting images and published SSH port trip lockout', () {
    expect(isSshFrontingContainer(_row(names: 'edge', image: 'traefik:v3')),
        isTrue);
    expect(
      isSshFrontingContainer(_row(names: 'vpn', image: 'tailscale/tailscale')),
      isTrue,
    );
    expect(
      isSshFrontingContainer(_row(names: 'wg', image: 'linuxserver/wireguard')),
      isTrue,
    );
    expect(
      isSshFrontingContainer(
        _row(names: 'bastion', image: 'linuxserver/openssh-server'),
      ),
      isTrue,
    );
    expect(
      isSshFrontingContainer(
        _row(names: 'web', image: 'busybox', publishedPorts: '2222\u219222'),
        sshPort: 22,
      ),
      isTrue,
    );
    expect(
      isSshFrontingContainer(
        _row(names: 'web', image: 'busybox', ports: '0.0.0.0:22->22/tcp'),
      ),
      isTrue,
    );
    expect(isSshFrontingContainer(_row(names: 'plex', image: 'linuxserver/plex')),
        isFalse);
  });

  test('stop and remove of SSH-fronting containers are lockout actions', () {
    final proxy = _row(names: 'traefik', image: 'traefik');
    expect(isLockoutContainerAction(ContainerVerb.stop.name, proxy), isTrue);
    expect(isLockoutContainerAction(ContainerVerb.remove.name, proxy), isTrue);
    expect(isLockoutContainerAction(ContainerVerb.restart.name, proxy), isFalse);
    expect(isLockoutContainerAction(ContainerVerb.start.name, proxy), isFalse);
    expect(
      isLockoutContainerAction(
        ContainerVerb.stop.name,
        _row(names: 'plex', image: 'linuxserver/plex'),
      ),
      isFalse,
    );
  });

  test('ContainerActionProbe risk follows lockout and remove', () {
    final proxy = _row(names: 'traefik', image: 'traefik');
    expect(
      ContainerActionProbe(row: proxy, verb: ContainerVerb.stop).risk,
      RiskLevel.destructive,
    );
    expect(
      ContainerActionProbe(row: proxy, verb: ContainerVerb.remove).risk,
      RiskLevel.destructive,
    );
    expect(
      ContainerActionProbe(
        row: _row(names: 'plex', image: 'linuxserver/plex'),
        verb: ContainerVerb.stop,
      ).risk,
      RiskLevel.mutate,
    );
    expect(
      ContainerActionProbe(
        row: _row(names: 'plex', image: 'linuxserver/plex'),
        verb: ContainerVerb.remove,
      ).risk,
      RiskLevel.destructive,
    );
  });
}
