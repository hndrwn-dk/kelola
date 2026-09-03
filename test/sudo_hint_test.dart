import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/sudo_hint.dart';

void expectNoBareSudoersBinaries(String text) {
  expect(text, isNot(contains('/bin/sh')));
  expect(text, isNot(contains('/usr/bin/sh')));
  expect(text, isNot(RegExp(r'/usr/bin/systemctl(?!\s+\S)')));
  expect(text, isNot(RegExp(r'/usr/bin/docker(?!\s+\S)')));
  expect(text, isNot(contains('NOPASSWD: ALL')));
}

void main() {
  test('generic hint never suggests a shell or bare mutate binaries', () {
    final hint = kelolaSudoHint(user: 'hendra');
    expectNoBareSudoersBinaries(hint.snippet);
    expectNoBareSudoersBinaries(hint.body);
    expect(hint.snippet, contains('visudo -f /etc/sudoers.d/kelola'));
    expect(hint.body.toLowerCase(), contains('journal'));
    expect(hint.body, contains('systemctl --user'));
  });

  test('nginx restart hint is that unit only, with visudo and polkit', () {
    final hint = kelolaSudoHint(
      user: 'hendra',
      context: SudoHintContext.systemd(
        unit: 'nginx.service',
        verb: 'restart',
      ),
    );
    expectNoBareSudoersBinaries(hint.snippet);
    expect(hint.snippet, contains('systemctl restart nginx.service'));
    expect(hint.snippet, contains('visudo -f /etc/sudoers.d/kelola'));
    expect(hint.snippet, contains('org.freedesktop.systemd1.manage-units'));
    expect(hint.snippet, contains('nginx.service'));
    expect(hint.snippet, isNot(contains('sshd.service')));
    expect(hint.snippet, contains('/etc/polkit-1/rules.d/49-kelola.rules'));
    expect(hint.snippet, isNot(contains('NOPASSWD: ALL')));
  });

  test('drop_caches hint cannot be made passwordless', () {
    final hint = kelolaSudoHint(
      user: 'hendra',
      context: const SudoHintContext.dropCaches(),
    );
    expectNoBareSudoersBinaries(hint.snippet);
    expect(hint.snippet.toLowerCase(), contains('cannot be passwordless'));
    expect(hint.snippet, isNot(contains('NOPASSWD:')));
  });

  test('footer sudo sentence reuses the title and names mutate failure', () {
    expect(sudoMutateWillFail, '$sudoRequiredTitle — mutate actions will fail');
  });

  test('detects SudoRequiredException and interactive sudo strings', () {
    expect(looksLikeSudoRequired(SudoRequiredException()), isTrue);
    expect(
      looksLikeSudoRequired('sudo: interactive authentication is required'),
      isTrue,
    );
    expect(looksLikeSudoRequired('sudo: a password is required'), isTrue);
    expect(looksLikeSudoRequired('Timed out waiting for SSH login.'), isFalse);
    expect(looksLikeSudoRequired('Host missing'), isFalse);
  });

  test('service control is honest and never invents unit counts', () {
    expect(
      serviceControlLabel(readOnly: true, sudoNeedsPassword: false),
      'none — read only',
    );
    expect(
      serviceControlLabel(readOnly: false, sudoNeedsPassword: true),
      'none — read only',
    );
    expect(
      serviceControlLabel(readOnly: false, sudoNeedsPassword: false),
      'sudo',
    );
    expect(serviceControlLabel(readOnly: false, sudoNeedsPassword: false),
        isNot(contains('units')));
  });

  test('package and firewall hints name the command, never a shell', () {
    final pkg = kelolaSudoHint(
      user: 'hendra',
      context: const SudoHintContext(
        kind: SudoHintKind.packages,
        binary: '/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold upgrade',
      ),
    );
    expectNoBareSudoersBinaries(pkg.snippet);
    expect(pkg.snippet, contains('/usr/bin/apt-get -y'));

    final fw = kelolaSudoHint(
      user: 'hendra',
      context: const SudoHintContext(
        kind: SudoHintKind.firewall,
        binary: '/usr/bin/firewall-cmd --add-port=8080/tcp',
      ),
    );
    expectNoBareSudoersBinaries(fw.snippet);
    expect(fw.snippet, contains('firewall-cmd --add-port=8080/tcp'));
  });
}
