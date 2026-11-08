import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/files/sftp_local_name.dart';
import 'package:path/path.dart' as p;

void main() {
  test('plain file names are safe', () {
    for (final name in ['notes.txt', '.bashrc', 'a b.log', '...', 'x..y']) {
      expect(isSafeSftpEntryName(name), isTrue, reason: name);
    }
  });

  test('server-chosen traversal names are rejected', () {
    for (final name in [
      '',
      '.',
      '..',
      '../kelola.sqlite',
      'report.txt/../../kelola.sqlite',
      '/etc/passwd',
      r'..\kelola.sqlite',
      'a\u0000b',
    ]) {
      expect(isSafeSftpEntryName(name), isFalse, reason: name);
    }
  });

  test('local path stays directly inside the transfer dir', () {
    final dir = p.join(Directory.systemTemp.path, 'kelola-transfers');
    expect(
      sftpLocalPathIn(dir, 'notes.txt'),
      p.join(p.normalize(p.absolute(dir)), 'notes.txt'),
    );
    expect(
      () => sftpLocalPathIn(dir, '../kelola.sqlite'),
      throwsArgumentError,
    );
    expect(
      () => sftpLocalPathIn(dir, 'x/../../kelola.sqlite'),
      throwsArgumentError,
    );
    expect(() => sftpLocalPathIn(dir, '..'), throwsArgumentError);
  });

  test('listing and local writes go through the name guards', () {
    final port = File('lib/data/ssh/dart_sftp_port.dart').readAsStringSync();
    expect(port, contains('isSafeSftpEntryName(n.filename)'));

    final screen =
        File('lib/presentation/screens/files_screen.dart').readAsStringSync();
    expect(screen, isNot(contains(r"/${e.name}')")));
    expect('sftpLocalPathIn('.allMatches(screen).length, 2);
  });
}
