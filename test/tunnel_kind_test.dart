import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/tunnels/tunnel_kind.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:kelola/domain/tunnels/tunnel_validation.dart';

TunnelTarget _t({
  TunnelKind kind = TunnelKind.local,
  String host = '127.0.0.1',
  int port = 9090,
  String path = '/',
  String label = 'Cockpit',
}) {
  return TunnelTarget(
    id: 't1',
    hostId: 'h1',
    label: label,
    remoteHost: host,
    remotePort: port,
    scheme: TunnelScheme.https,
    path: path,
    kind: kind,
  );
}

void main() {
  test('dynamic skips host and port; local still requires them', () {
    expect(validateTunnelTarget(_t(kind: TunnelKind.dynamic, host: '', port: 0)).isOk, isTrue);
    expect(validateTunnelTarget(_t(host: '', port: 9090)).isOk, isFalse);
    expect(validateTunnelTarget(_t(port: 0)).isOk, isFalse);
  });

  test('remote refuses a wildcard listen destination and keeps dest rules', () {
    expect(
      validateTunnelTarget(_t(kind: TunnelKind.remote, host: '0.0.0.0')).isOk,
      isFalse,
    );
    expect(
      validateTunnelTarget(_t(kind: TunnelKind.remote, host: '127.0.0.1', port: 22)).isOk,
      isTrue,
    );
  });

  test('kubectl needs a resource and a port; namespace is optional', () {
    expect(
      validateTunnelTarget(
        _t(kind: TunnelKind.kubectl, host: 'svc/nginx', port: 80, path: 'default'),
      ).isOk,
      isTrue,
    );
    expect(
      validateTunnelTarget(_t(kind: TunnelKind.kubectl, host: '', port: 80, path: '')).isOk,
      isFalse,
    );
    expect(
      validateTunnelTarget(
        _t(kind: TunnelKind.kubectl, host: 'svc/nginx', port: 80, path: '/bad'),
      ).isOk,
      isFalse,
    );
  });

  test('display meta and browser eligibility follow the kind', () {
    expect(tunnelTargetMeta(_t()), 'https://127.0.0.1:9090/');
    expect(tunnelTargetMeta(_t(kind: TunnelKind.dynamic)), 'socks5');
    expect(
      tunnelTargetMeta(_t(kind: TunnelKind.remote, host: '127.0.0.1', port: 22)),
      'remote · 127.0.0.1:22',
    );
    expect(
      tunnelTargetMeta(
        _t(kind: TunnelKind.kubectl, host: 'svc/nginx', port: 80, path: 'kube-system'),
      ),
      'kubectl · kube-system/svc/nginx:80',
    );
    expect(tunnelAllowsBrowser(_t()), isTrue);
    expect(tunnelAllowsBrowser(_t(kind: TunnelKind.dynamic)), isFalse);
    expect(tunnelAllowsBrowser(_t(kind: TunnelKind.remote)), isFalse);
    expect(tunnelAllowsBrowser(_t(kind: TunnelKind.kubectl, host: 'svc/x', port: 80)), isTrue);
  });

  test('kubectl port-forward command uses facts and loopback only', () {
    const facts = HostFacts(
      osId: 'debian',
      osVersionId: '12',
      init: InitSystem.systemd,
      systemdVersion: 252,
      pkg: PackageManager.apt,
      fw: FirewallBackend.ufw,
      hasJournald: true,
      journalReadable: true,
      arch: 'x86_64',
      runtimes: ['kubectl'],
    );
    final cmd = kubectlPortForwardCommand(
      facts,
      resource: 'svc/nginx',
      port: 80,
      namespace: 'default',
    );
    expect(cmd, contains('kubectl'));
    expect(cmd, contains('--address 127.0.0.1'));
    expect(cmd, contains('-n'));
    expect(cmd, contains('svc/nginx'));
    expect(cmd, contains(':80'));
    expect(cmd, isNot(contains('command -v')));
    expect(cmd, isNot(contains('0.0.0.0')));
    expect(parseKubectlForwardPort('Forwarding from 127.0.0.1:34567 -> 80'), 34567);
    expect(parseKubectlForwardPort('waiting'), isNull);
  });
}
