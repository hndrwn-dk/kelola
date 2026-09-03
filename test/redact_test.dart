import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/redaction/redact.dart';

void main() {
  test('redacts M7 patterns including adversarial key-shaped values', () {
    final out = redactText(
      'host nas-01 user hendr at 192.168.1.24 '
      'v6 2001:db8::1 email ops@example.com '
      'mac aa:bb:cc:dd:ee:ff '
      'password=hunter2 token=abc123 secret=shh Bearer eyJhbGciOi '
      'key ${'A' * 40}',
      hostnames: const ['nas-01'],
      usernames: const ['hendr'],
    );
    expect(out, contains('<HOST_1>'));
    expect(out, isNot(contains('nas-01')));
    expect(out, contains('<USER_1>'));
    expect(out, isNot(contains('hendr')));
    expect(out, contains('<IP_1>'));
    expect(out, isNot(contains('192.168.1.24')));
    expect(out, contains('<IP_2>'));
    expect(out, isNot(contains('2001:db8::1')));
    expect(out, contains('<EMAIL_1>'));
    expect(out, isNot(contains('ops@example.com')));
    expect(out, contains('<MAC_1>'));
    expect(out, isNot(contains('aa:bb:cc:dd:ee:ff')));
    expect(out, contains('password=<REDACTED>'));
    expect(out, contains('token=<REDACTED>'));
    expect(out, contains('secret=<REDACTED>'));
    expect(out, contains('Bearer <REDACTED>'));
    expect(out, contains('<REDACTED>'));
    expect(out, isNot(contains('hunter2')));
    expect(out, isNot(contains('A' * 40)));
  });

  test('redactEnv keeps keys and redacts secret-shaped values', () {
    final out = redactEnv([
      'PATH=/usr/bin',
      'PLEX_TOKEN=super-secret-token',
      'password=hunter2',
      'API_KEY=${'B' * 40}',
      'POSTGRES_HOST=192.168.1.10',
    ]);
    expect(out, contains('PATH=/usr/bin'));
    expect(out, contains('PLEX_TOKEN=<REDACTED>'));
    expect(out, isNot(contains('super-secret-token')));
    expect(out, contains('password=<REDACTED>'));
    expect(out, isNot(contains('hunter2')));
    expect(out, contains('API_KEY=<REDACTED>'));
    expect(out, isNot(contains('B' * 40)));
    expect(out.any((e) => e.startsWith('POSTGRES_HOST=') && e.contains('<IP_')),
        isTrue);
    expect(out, isNot(contains('192.168.1.10')));
  });
}
