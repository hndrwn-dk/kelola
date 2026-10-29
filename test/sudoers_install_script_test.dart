import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/sudo/sudoers_install_script.dart';

void main() {
  test('install script embeds content b64 and never embeds a password', () {
    const body = 'hendr ALL=(root) NOPASSWD: /usr/bin/dnf upgrade -y\n';
    final script = buildSudoersInstallScript(content: body);
    expect(script, contains('visudo -c'));
    expect(script, contains('/etc/sudoers.d/kelola'));
    expect(script, contains('0440'));
    expect(script, contains('base64'));
    expect(script, contains('KELOLA_SUDOERS_OK'));
    expect(script, isNot(contains(body)));
    expect(script.toLowerCase(), isNot(contains('password')));
  });

  test('parse success requires marker and file body', () {
    const body = '# header\nhendr ALL=(root) NOPASSWD: /usr/bin/dnf upgrade -y\n';
    final result = parseSudoersInstallOutput(
      stdout: '$body$sudoersInstallOkMarker\n',
      stderr: '',
      exitCode: 0,
      expectedContent: body,
    );
    expect(result.ok, isTrue);
    expect(result.verifiedContent, contains('dnf upgrade -y'));
  });

  test('parse fails when visudo would have aborted', () {
    final result = parseSudoersInstallOutput(
      stdout: '',
      stderr: 'syntax error',
      exitCode: 1,
      expectedContent: 'x',
    );
    expect(result.ok, isFalse);
  });
}
