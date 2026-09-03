import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/files/binary_detect.dart';
import 'package:kelola/domain/files/file_edit_save.dart';
import 'package:kelola/domain/files/sftp_entry.dart';
import 'package:kelola/domain/files/sftp_port.dart';

class _MemSftp implements SftpPort {
  final files = <String, List<int>>{};
  final writes = <String>[];

  @override
  Future<String> absolute(String path) async => path;

  @override
  Future<void> chmod(String path, int mode) async {}

  @override
  Future<List<SftpEntry>> listdir(String path) async => const [];

  @override
  Future<void> mkdir(String path) async {}

  @override
  Future<void> remove(String path) async => files.remove(path);

  @override
  Future<void> rename(String from, String to) async {
    final data = files.remove(from);
    if (data != null) {
      files[to] = data;
    }
  }

  @override
  Future<void> rmdir(String path) async {}

  @override
  Future<SftpEntry> stat(String path) async {
    final data = files[path];
    return SftpEntry(
      name: path.split('/').last,
      path: path,
      isDirectory: false,
      size: data?.length ?? 0,
      owner: 'u',
      group: 'u',
      permissions: 'rw-r--r--',
    );
  }

  @override
  Stream<List<int>> read(
    String path, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) async* {
    final data = files[path] ?? <int>[];
    onProgress?.call(data.length, data.length);
    yield data;
  }

  @override
  Future<void> write(
    String path,
    Stream<List<int>> data, {
    void Function(int done)? onProgress,
    TransferCancel? cancel,
  }) async {
    writes.add(path);
    final buf = <int>[];
    await for (final chunk in data) {
      if (cancel?.isCancelled == true) {
        throw const TransferCancelledException();
      }
      buf.addAll(chunk);
      onProgress?.call(buf.length);
    }
    files[path] = buf;
  }
}

void main() {
  test('dismissing the diff writes nothing and creates no bak', () async {
    final sftp = _MemSftp()..files['/etc/x.conf'] = utf8.encode('old\n');
    final dir = Directory.systemTemp.createTempSync('kelola-edit');
    addTearDown(() => dir.deleteSync(recursive: true));
    final original = File('${dir.path}/x.conf')..writeAsStringSync('old\n');
    await expectLater(
      saveEditedFile(
        sftp: sftp,
        remotePath: '/etc/x.conf',
        originalFile: original,
        editedText: 'new\n',
        confirmDiff: (_) async => false,
      ),
      throwsA(isA<SaveAbortedException>()),
    );
    expect(sftp.writes, isEmpty);
    expect(sftp.files.containsKey('/etc/x.conf.bak'), isFalse);
  });

  test('confirm writes bak first then the edited file', () async {
    final sftp = _MemSftp()..files['/etc/x.conf'] = utf8.encode('old\n');
    final dir = Directory.systemTemp.createTempSync('kelola-edit');
    addTearDown(() => dir.deleteSync(recursive: true));
    final original = File('${dir.path}/x.conf')..writeAsStringSync('old\n');
    await saveEditedFile(
      sftp: sftp,
      remotePath: '/etc/x.conf',
      originalFile: original,
      editedText: 'new\n',
      confirmDiff: (diff) async {
        expect(diff, contains('-old'));
        expect(diff, contains('+new'));
        return true;
      },
    );
    expect(sftp.writes, ['/etc/x.conf.bak', '/etc/x.conf']);
    expect(utf8.decode(sftp.files['/etc/x.conf.bak']!), 'old\n');
    expect(utf8.decode(sftp.files['/etc/x.conf']!), 'new\n');
  });

  test('open for edit refuses binary', () {
    expect(
      () => prepareTextEdit(List<int>.filled(8, 0)),
      throwsA(isA<BinaryFileException>()),
    );
  });
}
