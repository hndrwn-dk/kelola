import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/sudo_hint.dart';

void main() {
  test('sudoers line names Kelola mutate binaries, not NOPASSWD: ALL', () {
    final line = kelolaSudoersLine(user: 'hendra');
    expect(
      line,
      'hendra ALL=(root) NOPASSWD: /usr/sbin/reboot, /usr/sbin/poweroff, '
      '/usr/bin/systemctl, /usr/bin/kill, /bin/sh, /usr/bin/docker',
    );
    expect(line, isNot(contains('NOPASSWD: ALL')));
    expect(kelolaSudoersLine(), startsWith('YOURUSER ALL=(root) NOPASSWD:'));
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
}
