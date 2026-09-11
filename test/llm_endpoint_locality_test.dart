import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/llm/endpoint_locality.dart';

void main() {
  group('classifyEndpoint', () {
    void expectLocal(String? raw) {
      final uri = raw == null ? null : Uri.tryParse(raw);
      expect(
        classifyEndpoint(uri),
        EndpointLocality.local,
        reason: 'expected local: $raw',
      );
      expect(isLocalEndpoint(uri), isTrue, reason: raw);
    }

    void expectPublic(String? raw) {
      final Uri? uri;
      if (raw == null) {
        uri = null;
      } else if (raw == '') {
        uri = Uri.parse('');
      } else {
        uri = Uri.tryParse(raw) ?? Uri.parse(raw);
      }
      expect(
        classifyEndpoint(uri),
        EndpointLocality.public,
        reason: 'expected public: $raw',
      );
      expect(isLocalEndpoint(uri), isFalse, reason: raw);
    }

    test('IPv4 loopback is local', () {
      expectLocal('http://127.0.0.1:11434');
    });

    test('localhost variants are local', () {
      expectLocal('http://localhost:11434');
      expectLocal('http://LOCALHOST.:11434');
      expectLocal('http://ollama.localhost');
    });

    test('emulator host 10.0.2.2 is local', () {
      expectLocal('http://10.0.2.2:11434');
    });

    test('RFC1918 private IPv4 is local', () {
      expectLocal('http://192.168.1.50:11434');
      expectLocal('http://10.1.2.3');
      expectLocal('http://172.16.0.1');
      expectLocal('http://172.31.255.255');
    });

    test('172.15 and 172.32 are public (outside /12)', () {
      expectPublic('http://172.15.255.255');
      expectPublic('http://172.32.0.1');
    });

    test('CGNAT / Tailscale 100.64/10 is local', () {
      expectLocal('http://100.64.0.1');
      expectLocal('http://100.127.255.255');
    });

    test('outside CGNAT 100.x is public', () {
      expectPublic('http://100.63.255.255');
      expectPublic('http://100.128.0.1');
    });

    test('link-local 169.254 is local', () {
      expectLocal('http://169.254.1.1');
    });

    test('IPv6 loopback ULA and link-local are local', () {
      expectLocal('http://[::1]:11434');
      expectLocal('http://[fd12::1]');
      expectLocal('http://[fe80::1]');
    });

    test('IPv4-mapped IPv6 classifies by embedded IPv4', () {
      expectLocal('http://[::ffff:192.168.1.1]');
      expectPublic('http://[::ffff:8.8.8.8]');
    });

    test('documentation IPv6 is public', () {
      expectPublic('http://[2001:db8::1]');
    });

    test('local hostname suffixes are local', () {
      expectLocal('http://ollama.lan');
      expectLocal('http://gpu.home.arpa');
      expectLocal('http://box.local');
      expectLocal('http://svc.internal');
    });

    test('single-label host and unspecified addresses are public', () {
      expectPublic('http://ollama');
      expectPublic('http://0.0.0.0');
      expectPublic('http://[::]');
    });

    test('public hostnames and VPS IPs are public', () {
      expectPublic('https://llm.example.com');
      expectPublic('http://203.0.113.10:11434');
    });

    test('null empty and unparseable are public', () {
      expect(
        classifyEndpoint(null),
        EndpointLocality.public,
      );
      expect(
        classifyEndpoint(Uri.parse('')),
        EndpointLocality.public,
      );
      expect(
        classifyEndpoint(Uri.parse('not a url')),
        EndpointLocality.public,
      );
    });
  });
}
