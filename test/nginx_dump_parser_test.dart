import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/services/nginx_dump_parser.dart';
import 'package:kelola/domain/services/web_lens.dart';

String fixture(String name) =>
    File('test/fixtures/services/$name').readAsStringSync();

void main() {
  test('two server blocks with multiple server_name', () {
    final r = parseNginxDump(fixture('nginx_T_ubuntu.txt'));
    expect(r.vhosts, hasLength(3));
    final soon = r.vhosts[0];
    expect(soon.serverNames, ['soon.lab', 'www.soon.lab']);
    expect(soon.listen, ['443 ssl']);
    expect(soon.tls, isTrue);
    expect(soon.root, '/var/www/soon');
    expect(soon.certPath, '/etc/ssl/certs/soon.crt');
    expect(soon.sourceFile, '/etc/nginx/conf.d/soon.conf');
    final nocert = r.vhosts[1];
    expect(nocert.serverNames, ['nocert.lab']);
    expect(nocert.listen, ['443']);
    expect(nocert.tls, isFalse);
    expect(nocert.certPath, isNull);
    final def = r.vhosts[2];
    expect(def.serverNames, ['_']);
    expect(def.listen, ['80 default_server']);
    expect(def.root, '/var/www/html');
    expect(def.sourceFile, '/etc/nginx/sites-enabled/default');
    expect(r.truncated, isFalse);
  });

  test('server in a file included from stream is ignored', () {
    final r = parseNginxDump(fixture('nginx_T_alpine.txt'));
    expect(r.vhosts, hasLength(1));
    expect(r.vhosts.single.serverNames, ['app.local']);
    expect(r.vhosts.single.listen, ['80']);
  });

  test('server only counts directly under http', () {
    expect(
      parseNginxDump('http { server { server_name a; } }').vhosts,
      hasLength(1),
    );
    expect(
      parseNginxDump('events { http { server { server_name a; } } }').vhosts,
      isEmpty,
    );
    expect(
      parseNginxDump('http { upstream u { server { } } }').vhosts,
      isEmpty,
    );
    expect(parseNginxDump('mail { server { } }').vhosts, isEmpty);
  });

  test('relative include resolves against the main config directory', () {
    final r = parseNginxDump('''
# configuration file /etc/nginx/nginx.conf:
http { include conf.d/*.conf; }
# configuration file /etc/nginx/conf.d/a.conf:
server { server_name a; }
''');
    expect(r.vhosts.map((v) => v.serverNames.single), ['a']);
    // Included from stream: relative pattern must not be mistaken for http.
    final s = parseNginxDump('''
# configuration file /etc/nginx/nginx.conf:
stream { include conf.d/*.conf; }
# configuration file /etc/nginx/conf.d/a.conf:
server { server_name a; }
''');
    expect(s.vhosts, isEmpty);
  });

  test('file matching no include falls back to http', () {
    final r = parseNginxDump('''
# configuration file /etc/nginx/nginx.conf:
events {}
# configuration file /etc/other/x.conf:
server { server_name x; }
''');
    expect(r.vhosts.single.serverNames, ['x']);
  });

  test('a section header while blocks are open marks truncated', () {
    final r = parseNginxDump('''
# configuration file /etc/nginx/nginx.conf:
http { include /e/*.conf; }
# configuration file /e/x.conf:
server { server_name cut;
# configuration file /e/y.conf:
server { server_name y; }
''');
    expect(r.truncated, isTrue);
    expect(r.vhosts.map((v) => v.serverNames.single), ['y']);
  });

  test('multiple ssl_certificate kept in certPaths', () {
    final r = parseNginxDump('''http { server {
      ssl_certificate /c/rsa.pem; ssl_certificate_key /k/rsa.key;
      ssl_certificate /c/ec.pem; ssl_certificate_key /k/ec.key; } }''');
    expect(r.vhosts.single.certPath, '/c/rsa.pem');
    expect(r.vhosts.single.certPaths, ['/c/rsa.pem', '/c/ec.pem']);
    expect(r.toString(), isNot(contains('.key')));
  });

  test(r'${ scan cannot hide structure; mid-token quote is literal', () {
    final r = parseNginxDump(
      r'http { server { set $a ${x; } server { server_name b; } }',
    );
    expect(r.vhosts.map((v) => v.serverNames), [
      <String>[],
      ['b'],
    ]);
    final q = parseNginxDump('http { server { root /x/a"b; } }');
    expect(q.vhosts.single.root, '/x/a"b');
    expect(q.truncated, isFalse);
  });

  test('missing server_name gives empty list', () {
    final r = parseNginxDump('http { server { listen 80; } }');
    expect(r.vhosts.single.serverNames, isEmpty);
  });

  test('listen [::]:443 ssl http2 → tls true', () {
    final r = parseNginxDump(
      'http { server { listen 443 ssl http2; listen [::]:443 ssl http2; } }',
    );
    expect(r.vhosts.single.listen, ['443 ssl http2', '[::]:443 ssl http2']);
    expect(r.vhosts.single.tls, isTrue);
  });

  test('bare listen 443 without ssl is not tls', () {
    final r = parseNginxDump('http { server { listen 443; } }');
    expect(r.vhosts.single.tls, isFalse);
  });

  test('ssl_certificate captured, ssl_certificate_key ignored', () {
    final r = parseNginxDump(fixture('nginx_T_ubuntu.txt'));
    expect(r.vhosts[0].certPath, '/etc/ssl/certs/soon.crt');
    expect(r.toString(), isNot(contains('soon.key')));
    expect(r.vhosts.join(), isNot(contains('soon.key')));
    final k = parseNginxDump(
      'http { server { ssl_certificate_key /k/priv.pem; } }',
    );
    expect(k.vhosts.single.certPath, isNull);
    expect(k.toString(), isNot(contains('priv.pem')));
  });

  test('sourceFile from # configuration file header', () {
    final r = parseNginxDump(fixture('nginx_T_ubuntu.txt'));
    expect(r.vhosts[0].sourceFile, '/etc/nginx/conf.d/soon.conf');
    expect(r.vhosts[2].sourceFile, '/etc/nginx/sites-enabled/default');
  });

  test("comments and quoted braces don't break depth", () {
    const dump = '''
# configuration file /etc/nginx/nginx.conf:
http {
  # server { fake
  log_format main '{ "a": "b" } # not comment';
  server {
    server_name a.com; # trailing } comment
    add_header X "}{ # inside";
    listen
      80
      ;
    root "/var/www/my site";
  }
}
''';
    final r = parseNginxDump(dump);
    expect(r.truncated, isFalse);
    expect(r.vhosts, hasLength(1));
    expect(r.vhosts.single.serverNames, ['a.com']);
    expect(r.vhosts.single.listen, ['80']);
    expect(r.vhosts.single.root, '/var/www/my site');
  });

  test('CRLF and junk never throw', () {
    final crlf = 'http {\r\n server {\r\n server_name a.com;\r\n }\r\n}\r\n';
    expect(parseNginxDump(crlf).vhosts.single.serverNames, ['a.com']);
    for (final s in [
      '}}}}',
      '"unterminated',
      '{{{',
      ';;;',
      '\u0000\u0001',
      "'",
    ]) {
      expect(() => parseNginxDump(s), returnsNormally);
    }
    final long = 'http { server { server_name ${'a' * 200000}; } }';
    expect(parseNginxDump(long).vhosts, hasLength(1));
  });

  test('truncated dump keeps complete blocks and truncated == true', () {
    final r = parseNginxDump(fixture('nginx_T_truncated.txt'));
    expect(r.truncated, isTrue);
    expect(r.vhosts, hasLength(1));
    expect(r.vhosts.single.serverNames, ['a.example.com']);
    expect(r.vhosts.single.sourceFile, '/etc/nginx/conf.d/a.conf');
  });

  test('error_log/access_log paths collected', () {
    final r = parseNginxDump(fixture('nginx_T_ubuntu.txt'));
    expect(r.errorLogPaths, ['/var/log/nginx/error.log']);
    expect(r.accessLogPaths, ['/var/log/nginx/access.log']);
    final a = parseNginxDump(fixture('nginx_T_alpine.txt'));
    expect(a.errorLogPaths, ['/var/log/nginx/error.log']);
    final m = parseNginxDump('''
error_log stderr; error_log syslog:server=x; error_log memory:32m;
error_log /var/log/a.log; error_log /var/log/a.log;
http { access_log off; access_log /var/log/\$host.log;
  server { access_log /var/log/s.log main; error_log /var/log/s.err; } }
''');
    expect(m.errorLogPaths, ['/var/log/a.log', '/var/log/s.err']);
    expect(m.accessLogPaths, ['/var/log/s.log']);
  });

  test('empty input → empty result', () {
    final r = parseNginxDump('');
    expect(r.vhosts, isEmpty);
    expect(r.errorLogPaths, isEmpty);
    expect(r.accessLogPaths, isEmpty);
    expect(r.truncated, isFalse);
  });

  test('WebCert.daysLeft', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    expect(const WebCert(path: 'p').daysLeft(now), isNull);
    expect(
      WebCert(path: 'p', notAfter: DateTime.utc(2026, 1, 11, 11)).daysLeft(now),
      9,
    );
    expect(
      WebCert(
        path: 'p',
        notAfter: DateTime.utc(2025, 12, 31, 11),
      ).daysLeft(now),
      -2,
    );
  });
}
