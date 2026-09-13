import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/tunnels/tunnel_presets.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';

void main() {
  const userFields = (
    label: 'My service',
    remoteHost: '10.0.0.5',
    remotePort: 8080,
    scheme: TunnelScheme.http,
    path: '/app',
  );

  TunnelTarget _apply(TunnelPreset preset) {
    return TunnelPresets.apply(
      preset: preset,
      id: 't1',
      hostId: 'h1',
      label: userFields.label,
      remoteHost: userFields.remoteHost,
      remotePort: userFields.remotePort,
      scheme: userFields.scheme,
      path: userFields.path,
    );
  }

  test('Cockpit preset fills port scheme and path', () {
    final target = _apply(TunnelPreset.cockpit);
    expect(target.label, 'Cockpit');
    expect(target.remotePort, 9090);
    expect(target.scheme, TunnelScheme.https);
    expect(target.path, '/');
  });

  test('Portainer preset fills port scheme and path', () {
    final target = _apply(TunnelPreset.portainer);
    expect(target.label, 'Portainer');
    expect(target.remotePort, 9443);
    expect(target.scheme, TunnelScheme.https);
    expect(target.path, '/');
  });

  test('Grafana preset fills port scheme and path', () {
    final target = _apply(TunnelPreset.grafana);
    expect(target.label, 'Grafana');
    expect(target.remotePort, 3000);
    expect(target.scheme, TunnelScheme.http);
    expect(target.path, '/');
  });

  test('Prometheus preset fills port scheme and path', () {
    final target = _apply(TunnelPreset.prometheus);
    expect(target.label, 'Prometheus');
    expect(target.remotePort, 9090);
    expect(target.scheme, TunnelScheme.http);
    expect(target.path, '/');
  });

  test('Custom preset leaves user fields', () {
    final target = _apply(TunnelPreset.custom);
    expect(target.label, userFields.label);
    expect(target.remoteHost, userFields.remoteHost);
    expect(target.remotePort, userFields.remotePort);
    expect(target.scheme, userFields.scheme);
    expect(target.path, userFields.path);
  });
}
