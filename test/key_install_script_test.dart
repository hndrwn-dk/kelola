import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/enrollment/key_install_script.dart';

void main() {
  const body = 'AAAA'; // placeholder; real tests use valid-looking base64 without forbidden chars
  const line = 'ecdsa-sha2-nistp256 AAAA kelola';

  test('rejects quote backslash newline whitespace in body or comment tokens', () {
    expect(() => assertSafeKeyInstallToken("abc'def", label: 'body'), throwsArgumentError);
    expect(() => assertSafeKeyInstallToken('abc"def', label: 'body'), throwsArgumentError);
    expect(() => assertSafeKeyInstallToken(r'abc\def', label: 'body'), throwsArgumentError);
    expect(() => assertSafeKeyInstallToken('abc def', label: 'body'), throwsArgumentError);
    expect(() => assertSafeKeyInstallToken('abc\ndef', label: 'body'), throwsArgumentError);
    expect(() => assertSafeKeyInstallToken('AAAA', label: 'body'), returnsNormally);
  });

  test('buildKeyInstallScript rejects unsafe comment in fullLine', () {
    const unsafeComments = [
      "ecdsa-sha2-nistp256 AAAA kel'ola",
      'ecdsa-sha2-nistp256 AAAA kel"ola',
      r'ecdsa-sha2-nistp256 AAAA kel\ola',
      'ecdsa-sha2-nistp256 AAAA kel ola',
      'ecdsa-sha2-nistp256 AAAA kel\nola',
    ];
    for (final fullLine in unsafeComments) {
      expect(
        () => buildKeyInstallScript(keyBody: body, fullLine: fullLine),
        throwsArgumentError,
        reason: fullLine,
      );
    }
  });

  test('buildKeyInstallRemoteCommand rejects unsafe comment in fullLine', () {
    expect(
      () => buildKeyInstallRemoteCommand(
        keyBody: body,
        fullLine: 'ecdsa-sha2-nistp256 AAAA kel ola',
      ),
      throwsArgumentError,
    );
  });

  test('remote command invokes sh not bash', () {
    final cmd = buildKeyInstallRemoteCommand(keyBody: body, fullLine: line);
    expect(cmd.contains('bash'), isFalse);
    expect(cmd.contains('sh -s'), isTrue);
    expect(cmd.contains('base64'), isTrue);
  });

  test('POSIX sh: three existing keys keep all three plus ours', () async {
    final dir = await Directory.systemTemp.createTemp('kelola-ak-');
    addTearDown(() => dir.delete(recursive: true));
    final home = dir.path;
    final ssh = Directory('$home/.ssh')..createSync();
    File('${ssh.path}/authorized_keys').writeAsStringSync(
      'ssh-ed25519 AAA existing1\n'
      'ssh-ed25519 BBB existing2\n'
      'ssh-ed25519 CCC existing3\n',
    );
    final script = buildKeyInstallScript(keyBody: body, fullLine: line);
    final scriptFile = File('${dir.path}/install.sh')..writeAsStringSync(script);
    final result = await Process.run(
      'sh',
      [scriptFile.path],
      environment: {...Platform.environment, 'HOME': home},
    );
    expect(result.exitCode, 0);
    final ak = File('${ssh.path}/authorized_keys').readAsStringSync();
    expect(ak.split('\n').where((l) => l.isNotEmpty).length, 4);
    expect(ak.contains('existing1'), isTrue);
    expect(ak.contains(line), isTrue);
    expect(result.stdout.toString(), contains('CREATED_SSH=0'));
  });

  test('POSIX sh: no trailing newline keeps last key and ours valid', () async {
    final dir = await Directory.systemTemp.createTemp('kelola-ak-nl-');
    addTearDown(() => dir.delete(recursive: true));
    final home = dir.path;
    Directory('$home/.ssh').createSync();
    File('$home/.ssh/authorized_keys').writeAsStringSync(
      'ssh-ed25519 AAA existing1', // no trailing newline
    );
    final script = buildKeyInstallScript(keyBody: body, fullLine: line);
    final scriptFile = File('${dir.path}/install.sh')..writeAsStringSync(script);
    final result = await Process.run(
      'sh',
      [scriptFile.path],
      environment: {...Platform.environment, 'HOME': home},
    );
    expect(result.exitCode, 0);
    final lines = File('$home/.ssh/authorized_keys')
        .readAsStringSync()
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();
    expect(lines, ['ssh-ed25519 AAA existing1', line]);
  });

  test('POSIX sh: second run exits 3 and does not duplicate', () async {
    final dir = await Directory.systemTemp.createTemp('kelola-ak-id-');
    addTearDown(() => dir.delete(recursive: true));
    final home = dir.path;
    Directory('$home/.ssh').createSync();
    final script = buildKeyInstallScript(keyBody: body, fullLine: line);
    final scriptFile = File('${dir.path}/install.sh')..writeAsStringSync(script);
    Future<ProcessResult> run() => Process.run(
          'sh',
          [scriptFile.path],
          environment: {...Platform.environment, 'HOME': home},
        );
    expect((await run()).exitCode, 0);
    final second = await run();
    expect(second.exitCode, 3);
    final ak = File('$home/.ssh/authorized_keys').readAsStringSync();
    expect(RegExp(RegExp.escape(line)).allMatches(ak).length, 1);
  });

  test('POSIX sh: creates ~/.ssh 700 when missing', () async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final dir = await Directory.systemTemp.createTemp('kelola-ak-mk-');
    addTearDown(() => dir.delete(recursive: true));
    final home = dir.path;
    final script = buildKeyInstallScript(keyBody: body, fullLine: line);
    final scriptFile = File('${dir.path}/install.sh')..writeAsStringSync(script);
    final result = await Process.run(
      'sh',
      [scriptFile.path],
      environment: {...Platform.environment, 'HOME': home},
    );
    expect(result.exitCode, 0);
    expect(result.stdout.toString(), contains('CREATED_SSH=1'));
    final mode = File('$home/.ssh').statSync().mode & 0x1FF;
    expect(mode, 0x1C0); // 0700
  });

  test('parseKeyInstallAppendResult maps exit 0 to appended with stdout fields', () {
    final a = parseKeyInstallAppendResult(
      exitCode: 0,
      stdout: 'HOME_MODE=drwx------\nCREATED_SSH=1\n',
    );
    expect(a.kind, KeyInstallAppendKind.appended);
    expect(a.homeMode, 'drwx------');
    expect(a.createdSsh, isTrue);
    expect(homeModeGroupOrWorldWritable('drwxrwxr-x'), isTrue);
    expect(homeModeGroupOrWorldWritable('drwxr-xr-x'), isFalse);
    expect(homeModeGroupOrWorldWritable('drwxr-xr-x.'), isFalse);
  });

  test('parseKeyInstallAppendResult maps exit 3 to alreadyPresent', () {
    final a = parseKeyInstallAppendResult(
      exitCode: 3,
      stdout: 'HOME_MODE=drwx------\nCREATED_SSH=0\n',
    );
    expect(a.kind, KeyInstallAppendKind.alreadyPresent);
    expect(a.homeMode, 'drwx------');
    expect(a.createdSsh, isFalse);
  });

  test('parseKeyInstallAppendResult maps non-0/3 exit to failed', () {
    final a = parseKeyInstallAppendResult(
      exitCode: 1,
      stdout: 'HOME_MODE=drwx------\nCREATED_SSH=0\n',
    );
    expect(a.kind, KeyInstallAppendKind.failed);
    expect(a.homeMode, 'drwx------');
    expect(a.createdSsh, isFalse);
  });
}
