import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/services/apache_vhosts_parser.dart';

String fixture(String name) =>
    File('test/fixtures/services/$name').readAsStringSync();

void main() {
  test('namevhost with source file and line', () {
    final v = parseApacheVhosts(fixture('httpd_S_rocky.txt'));
    expect(v, hasLength(3));
    expect(v[0].serverNames.first, 'example.com');
    expect(v[0].sourceFile, '/etc/httpd/conf.d/ssl.conf:56');
    expect(v[0].listen, ['*:443']);
    expect(v[0].root, isNull);
    expect(v[0].certPath, isNull);
    expect(v[1].serverNames, ['other.example']);
    expect(v[2].serverNames, ['rocky.lab']);
    expect(v[2].listen, ['*:80']);
    expect(v[2].sourceFile, '/etc/httpd/conf.d/site.conf:1');
  });

  test('alias lines added to serverNames', () {
    final v = parseApacheVhosts(fixture('httpd_S_rocky.txt'));
    expect(v[0].serverNames, ['example.com', 'www.example.com']);
    expect(v[1].serverNames, ['other.example']);
  });

  test('default server line', () {
    final v = parseApacheVhosts(fixture('httpd_S_rocky.txt'));
    expect(v.where((e) => e.serverNames.contains('example.com')), hasLength(1));
  });

  test('port 443 → tls true', () {
    final v = parseApacheVhosts(fixture('httpd_S_rocky.txt'));
    expect(v[0].tls, isTrue);
    expect(v[2].tls, isFalse);
    final w = parseApacheVhosts(
      '[::]:443  is a NameVirtualHost\r\n'
      '  port 443 namevhost a.b (/x/y.conf:3)\r\n'
      '192.0.2.1:8443  c.d (/x/z.conf:9)\r\n',
    );
    expect(w, hasLength(2));
    expect(w[0].listen, ['[::]:443']);
    expect(w[0].tls, isTrue);
    expect(w[0].sourceFile, '/x/y.conf:3');
    expect(w[1].listen, ['192.0.2.1:8443']);
    expect(w[1].tls, isFalse);
  });

  test('junk → empty', () {
    expect(parseApacheVhosts(''), isEmpty);
    expect(
      parseApacheVhosts('\u0000\u{1F600} port namevhost ((( \n alias\n'),
      isEmpty,
    );
    expect(
      parseApacheVhosts('${' ' * 100000}port 1 namevhost ${'(' * 50000}'),
      isEmpty,
    );
  });

  test('config dir by package manager', () {
    HostFacts f(PackageManager p) => HostFacts.undiscovered.copyWith(pkg: p);
    for (final p in [
      PackageManager.dnf,
      PackageManager.yum,
      PackageManager.zypper,
    ]) {
      expect(apacheConfigDir(f(p)), '/etc/httpd');
      expect(apacheDefaultLogs(f(p)).error, '/var/log/httpd/error_log');
      expect(apacheDefaultLogs(f(p)).access, '/var/log/httpd/access_log');
    }
    expect(apacheConfigDir(f(PackageManager.apt)), '/etc/apache2');
    expect(
      apacheDefaultLogs(f(PackageManager.apt)).error,
      '/var/log/apache2/error.log',
    );
    expect(
      apacheDefaultLogs(f(PackageManager.apt)).access,
      '/var/log/apache2/access.log',
    );
  });
}
