import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:kelola/domain/tunnels/tunnel_validation.dart';

TunnelTarget _target({
  String label = 'Cockpit',
  String remoteHost = '127.0.0.1',
  int remotePort = 9090,
  TunnelScheme scheme = TunnelScheme.https,
  String path = '/',
}) {
  return TunnelTarget(
    id: 't1',
    hostId: 'h1',
    label: label,
    remoteHost: remoteHost,
    remotePort: remotePort,
    scheme: scheme,
    path: path,
  );
}

void main() {
  group('validateTunnelTarget remotePort', () {
    test('accepts 1 and 65535', () {
      expect(validateTunnelTarget(_target(remotePort: 1)).isOk, isTrue);
      expect(validateTunnelTarget(_target(remotePort: 65535)).isOk, isTrue);
    });

    test('rejects 0 and 65536', () {
      expect(validateTunnelTarget(_target(remotePort: 0)).isOk, isFalse);
      expect(validateTunnelTarget(_target(remotePort: 65536)).isOk, isFalse);
    });
  });

  group('validateTunnelTarget remoteHost', () {
    test('accepts hostname and IPv4', () {
      expect(validateTunnelTarget(_target(remoteHost: 'localhost')).isOk, isTrue);
      expect(validateTunnelTarget(_target(remoteHost: '127.0.0.1')).isOk, isTrue);
    });

    test('rejects empty host', () {
      expect(validateTunnelTarget(_target(remoteHost: '')).isOk, isFalse);
      expect(validateTunnelTarget(_target(remoteHost: '   ')).isOk, isFalse);
    });

    test('rejects 0.0.0.0 with specific message', () {
      final result = validateTunnelTarget(_target(remoteHost: '0.0.0.0'));
      expect(result.isOk, isFalse);
      expect(result.error, 'Remote host cannot be 0.0.0.0');
    });

    test('rejects scheme, port, path, and spaces', () {
      expect(validateTunnelTarget(_target(remoteHost: 'http://localhost')).isOk, isFalse);
      expect(validateTunnelTarget(_target(remoteHost: 'localhost:8080')).isOk, isFalse);
      expect(validateTunnelTarget(_target(remoteHost: 'localhost/admin')).isOk, isFalse);
      expect(validateTunnelTarget(_target(remoteHost: 'local host')).isOk, isFalse);
    });
  });

  group('validateTunnelTarget path', () {
    test('accepts empty and slash-prefixed paths', () {
      expect(validateTunnelTarget(_target(path: '')).isOk, isTrue);
      expect(validateTunnelTarget(_target(path: '/')).isOk, isTrue);
      expect(validateTunnelTarget(_target(path: '/dashboard')).isOk, isTrue);
    });

    test('rejects path without leading slash', () {
      expect(validateTunnelTarget(_target(path: 'dashboard')).isOk, isFalse);
    });
  });

  group('validateTunnelTarget label', () {
    test('accepts trimmed non-empty label up to 40 chars', () {
      expect(validateTunnelTarget(_target(label: '  Cockpit  ')).isOk, isTrue);
      expect(validateTunnelTarget(_target(label: 'a' * 40)).isOk, isTrue);
    });

    test('rejects empty or overlong label', () {
      expect(validateTunnelTarget(_target(label: '')).isOk, isFalse);
      expect(validateTunnelTarget(_target(label: '   ')).isOk, isFalse);
      expect(validateTunnelTarget(_target(label: 'a' * 41)).isOk, isFalse);
    });
  });

  group('ActiveTunnel.url', () {
    ActiveTunnel _active({required String path, int localPort = 54321}) {
      return ActiveTunnel(
        id: 'a1',
        target: _target(path: path),
        hostAlias: 'web-01',
        localPort: localPort,
        state: TunnelState.listening,
        openedAtUtc: DateTime.utc(2026, 9, 13),
        openChannels: 0,
      );
    }

    test('builds valid URIs without double slashes', () {
      for (final path in ['', '/', '/dashboard']) {
        final url = _active(path: path).url;
        expect(url.host, '127.0.0.1');
        expect(url.scheme, 'https');
        expect(url.port, 54321);
        final afterScheme = url.toString().substring('${url.scheme}://'.length);
        expect(afterScheme, isNot(startsWith('//')));
        if (path.isEmpty) {
          expect(url.path, isEmpty);
          expect(url.toString(), 'https://127.0.0.1:54321');
        } else {
          expect(url.path, path);
          expect(url.toString(), 'https://127.0.0.1:54321$path');
        }
      }
    });
  });
}
