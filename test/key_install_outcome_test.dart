import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/enrollment/key_install_outcome.dart';
import 'package:kelola/domain/enrollment/key_install_script.dart';

void main() {
  const line = 'ecdsa-sha2-nistp256 AAAA kelola';

  test('appended and verified is success', () {
    final r = buildKeyInstallReport(
      append: const KeyInstallAppendResult(
        kind: KeyInstallAppendKind.appended,
        homeMode: 'drwx------',
        createdSsh: false,
      ),
      verifyOk: true,
      fullLine: line,
    );
    expect(r.success, isTrue);
    expect(r.title.toLowerCase(), contains('installed'));
  });

  test('already present and verified does not claim added', () {
    final r = buildKeyInstallReport(
      append: const KeyInstallAppendResult(
        kind: KeyInstallAppendKind.alreadyPresent,
        homeMode: 'drwx------',
        createdSsh: false,
      ),
      verifyOk: true,
      fullLine: line,
    );
    expect(r.success, isTrue);
    expect(r.body.toLowerCase(), isNot(contains('added')));
    expect(r.body.toLowerCase(), contains('already'));
  });

  test('append ok verify fail shows line, removal hint, causes', () {
    final r = buildKeyInstallReport(
      append: const KeyInstallAppendResult(
        kind: KeyInstallAppendKind.appended,
        homeMode: 'drwxrwxr-x',
        createdSsh: true,
      ),
      verifyOk: false,
      fullLine: line,
    );
    expect(r.success, isFalse);
    expect(r.body, contains(line));
    expect(r.body.toLowerCase(), contains('authorized_keys'));
    expect(r.body.toLowerCase(), contains('writable'));
    expect(r.body.toLowerCase(), contains('selinux'));
    expect(r.body, contains('AuthorizedKeysFile'));
  });

  test('already present verify fail mentions options', () {
    final r = buildKeyInstallReport(
      append: const KeyInstallAppendResult(
        kind: KeyInstallAppendKind.alreadyPresent,
        homeMode: 'drwx------',
        createdSsh: false,
      ),
      verifyOk: false,
      fullLine: line,
    );
    expect(r.success, isFalse);
    expect(r.body.toLowerCase(), contains('option'));
    expect(r.body, contains('AuthorizedKeysFile'));
  });
}
