import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/files/text_diff.dart';

void main() {
  test('identical text has no hunks', () {
    expect(unifiedDiff('a\nb\n', 'a\nb\n', path: '/tmp/a'), isEmpty);
  });

  test('changed config shows unified hunks the user can dismiss', () {
    final diff = unifiedDiff(
      'listen 80;\n',
      'listen 443;\n',
      path: '/etc/nginx/nginx.conf',
    );
    expect(diff, contains('--- /etc/nginx/nginx.conf'));
    expect(diff, contains('+++ /etc/nginx/nginx.conf'));
    expect(diff, contains('-listen 80;'));
    expect(diff, contains('+listen 443;'));
  });
}
