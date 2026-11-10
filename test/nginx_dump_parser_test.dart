import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/services/nginx_dump_parser.dart';
import 'package:kelola/domain/services/service_catalog.dart';
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

  group('include from inside a server block (real section layout)', () {
    test('snippet cert, listen and root reach every vhost that includes it', () {
      // Real `nginx -T` (1.24, this layout: the snippet is printed once,
      // right after the first file that includes it).
      final r = parseNginxDump(fixture('nginx_T_snakeoil.txt'));
      expect(r.truncated, isFalse);
      expect(r.vhosts, hasLength(2));
      final def = r.vhosts[0];
      expect(def.serverNames, ['_']);
      expect(def.sourceFile, '/etc/nginx/sites-enabled/default');
      expect(def.certPaths, ['/etc/ssl/certs/ssl-cert-snakeoil.pem']);
      expect(def.certPath, '/etc/ssl/certs/ssl-cert-snakeoil.pem');
      expect(def.tls, isTrue);
      // Included after the snippet was printed: still attributed.
      final shop = r.vhosts[1];
      expect(shop.serverNames, ['shop.lab']);
      expect(shop.certPaths, ['/etc/ssl/certs/ssl-cert-snakeoil.pem']);
      expect(r.toString(), isNot(contains('.key')));
      expect(r.toString(), isNot(contains('snakeoil.key')));

      final lens = WebLens(
        id: ServiceId.nginx,
        readAt: DateTime.utc(2026, 11, 10),
        vhosts: r.vhosts,
      );
      expect(
        lens.findings.where(
          (f) => f.kind == WebFindingKind.listens443WithoutCert,
        ),
        isEmpty,
      );
    });

    test('snippet directives: listen, root, server_name; a nested include too', () {
      final r = parseNginxDump('''
# configuration file /etc/nginx/nginx.conf:
http { include /etc/nginx/sites/*; }
# configuration file /etc/nginx/sites/a:
server {
  include /etc/nginx/snip/tls.conf;
  location / { include /etc/nginx/snip/loc.conf; }
}
# configuration file /etc/nginx/snip/tls.conf:
listen 443 ssl;
server_name a.example;
root /srv/a;
include /etc/nginx/snip/cert.conf;
# configuration file /etc/nginx/snip/cert.conf:
ssl_certificate /etc/ssl/a.pem;
ssl_certificate_key /etc/ssl/a.key;
# configuration file /etc/nginx/snip/loc.conf:
root /srv/not-the-vhost-root;
ssl_certificate /etc/ssl/location-level.pem;
''');
      final v = r.vhosts.single;
      expect(v.listen, ['443 ssl']);
      expect(v.tls, isTrue);
      expect(v.serverNames, ['a.example']);
      expect(v.root, '/srv/a');
      // Only directives at the server's own level count.
      expect(v.certPaths, ['/etc/ssl/a.pem']);
      expect(r.toString(), isNot(contains('.key')));
    });

    test('a file included at http level never adds to a vhost', () {
      final r = parseNginxDump('''
# configuration file /etc/nginx/nginx.conf:
http { include /etc/nginx/conf.d/*.conf; server { server_name a; } }
# configuration file /etc/nginx/conf.d/x.conf:
ssl_certificate /etc/ssl/http-level.pem;
server { server_name b; }
''');
      expect(r.vhosts.map((v) => v.serverNames.single), ['a', 'b']);
      expect(r.vhosts.every((v) => v.certPaths.isEmpty), isTrue);
    });
  });

  group('hostile input is bounded', () {
    test('200k nested blocks with includes: fast, truncated, no throw', () {
      final sw = Stopwatch()..start();
      final r = parseNginxDump('a{include b;' * 200000);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(r.truncated, isTrue);
      expect(r.vhosts, isEmpty);
    });

    test('nesting past 64 levels is ignored safely and marks truncated', () {
      final deep = '${'x{' * 70}server { server_name deep; }${'}' * 70}';
      final r = parseNginxDump('http { server { server_name ok; } $deep '
          'server { server_name after; } }');
      expect(r.truncated, isTrue);
      expect(r.vhosts.map((v) => v.serverNames.single), ['ok', 'after']);
      // 64 levels exactly is fine.
      final ok = parseNginxDump('${'x{' * 63}${'}' * 63}');
      expect(ok.truncated, isFalse);
    });

    test('50k includes and many sections: fast, capped, no throw', () {
      final b = StringBuffer('# configuration file /etc/nginx/nginx.conf:\n'
          'http {\n');
      for (var i = 0; i < 50000; i++) {
        b.write('include /etc/nginx/i$i/*.conf;\n');
      }
      b.write('}\n');
      for (var i = 0; i < 5000; i++) {
        b.write('# configuration file /etc/nginx/s$i/x.conf:\n'
            'server { server_name s$i; }\n');
      }
      final sw = Stopwatch()..start();
      final r = parseNginxDump(b.toString());
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(r.truncated, isTrue);
      expect(r.vhosts, isNotEmpty);
    });

    test('includes inside included files cannot blow up the vhost links', () {
      final b = StringBuffer('# configuration file /etc/nginx/nginx.conf:\n'
          'http { include /s/*; }\n');
      for (var i = 0; i < 1000; i++) {
        b.write('# configuration file /s/a$i:\nserver { include /s/*; }\n');
      }
      for (var i = 0; i < 1000; i++) {
        b.write('# configuration file /s/b$i:\ninclude /s/*;\nlisten 443 ssl;\n');
      }
      final sw = Stopwatch()..start();
      final r = parseNginxDump(b.toString());
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(r.truncated, isTrue);
      for (final v in r.vhosts) {
        expect(v.listen.length, lessThanOrEqualTo(256));
      }
    });

    test('nested includes in server blocks stay bounded', () {
      final b = StringBuffer('# configuration file /etc/nginx/nginx.conf:\n'
          'http { include /s/*; }\n');
      for (var i = 0; i < 3000; i++) {
        b.write('# configuration file /s/$i:\n'
            'server { include /s/*; include /s/*; }\n');
      }
      final sw = Stopwatch()..start();
      final r = parseNginxDump(b.toString());
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(r.vhosts, isNotEmpty);
    });
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
