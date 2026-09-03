import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/files/sftp_entry.dart';
import 'package:kelola/domain/files/sftp_list_view.dart';

SftpEntry _e(String name, {bool dir = false, int size = 0}) {
  return SftpEntry(
    name: name,
    path: '/home/u/$name',
    isDirectory: dir,
    size: size,
    owner: 'u',
    group: 'u',
    permissions: dir ? 'rwxr-xr-x' : 'rw-r--r--',
  );
}

void main() {
  test('chips filter hidden names; dirs sort first; empty copy when none match', () {
    final rows = [
      _e('.cache', dir: true),
      _e('notes.txt', size: 12),
      _e('bin', dir: true),
      _e('.'),
      _e('..'),
    ];
    final hiddenOff = SftpListView.build(rows, showHidden: false);
    expect(hiddenOff.rows.map((e) => e.name), ['bin', 'notes.txt']);
    expect(hiddenOff.hiddenCount, 1);
    expect(hiddenOff.emptyCopy, isNull);

    final onlyHidden = SftpListView.build([_e('.env')], showHidden: false);
    expect(onlyHidden.rows, isEmpty);
    expect(onlyHidden.emptyCopy, isNotNull);

    final shown = SftpListView.build(rows, showHidden: true);
    expect(shown.rows.map((e) => e.name), ['.cache', 'bin', 'notes.txt']);
  });

  test('owner and mode come from longname when present', () {
    final e = sftpEntryFromListing(
      name: 'sshd_config',
      path: '/etc/ssh/sshd_config',
      longname: '-rw-r--r--    1 root     root         3349 Jan  1 00:00 sshd_config',
      isDirectory: false,
      size: 3349,
      uid: 0,
      gid: 0,
      mode: 0x1A4,
      mtimeSeconds: 0,
    );
    expect(e.owner, 'root');
    expect(e.group, 'root');
    expect(e.permissions, 'rw-r--r--');
  });
}
