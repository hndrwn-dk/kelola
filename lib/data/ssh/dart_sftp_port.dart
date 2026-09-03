import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/files/sftp_entry.dart';
import 'package:kelola/domain/files/sftp_path.dart';
import 'package:kelola/domain/files/sftp_port.dart';

class DartSshSftpPort implements SftpPort {
  DartSshSftpPort(this._sftp);

  final SftpClient _sftp;

  @override
  Future<String> absolute(String path) {
    return _wrap(() => _sftp.absolute(path));
  }

  @override
  Future<void> chmod(String path, int mode) {
    return _wrap(() async {
      final attrs = await _sftp.stat(path);
      final typeBits = (attrs.mode?.value ?? 0) & ~0x1FF;
      await _sftp.setStat(
        path,
        SftpFileAttrs(mode: SftpFileMode.value(typeBits | (mode & 0x1FF))),
      );
    });
  }

  @override
  Future<List<SftpEntry>> listdir(String path) {
    return _wrap(() async {
      final names = await _sftp.listdir(path);
      return [
        for (final n in names)
          sftpEntryFromListing(
            name: n.filename,
            path: joinSftpPath(path, n.filename),
            longname: n.longname,
            isDirectory: n.attr.isDirectory,
            isSymlink: n.attr.isSymbolicLink,
            size: n.attr.size,
            uid: n.attr.userID,
            gid: n.attr.groupID,
            mode: n.attr.mode?.value,
            mtimeSeconds: n.attr.modifyTime,
          ),
      ];
    });
  }

  @override
  Future<void> mkdir(String path) => _wrap(() => _sftp.mkdir(path));

  @override
  Future<void> remove(String path) => _wrap(() => _sftp.remove(path));

  @override
  Future<void> rename(String from, String to) {
    return _wrap(() => _sftp.rename(from, to));
  }

  @override
  Future<void> rmdir(String path) => _wrap(() => _sftp.rmdir(path));

  @override
  Future<SftpEntry> stat(String path) {
    return _wrap(() async {
      final attrs = await _sftp.stat(path);
      return sftpEntryFromListing(
        name: sftpBasename(path),
        path: path,
        longname: '',
        isDirectory: attrs.isDirectory,
        isSymlink: attrs.isSymbolicLink,
        size: attrs.size,
        uid: attrs.userID,
        gid: attrs.groupID,
        mode: attrs.mode?.value,
        mtimeSeconds: attrs.modifyTime,
      );
    });
  }

  @override
  Stream<List<int>> read(
    String path, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) async* {
    final file = await _wrap(() => _sftp.open(path, mode: SftpFileOpenMode.read));
    try {
      final attrs = await _wrap(file.stat);
      final total = attrs.size;
      await for (final chunk in file.read(
        onProgress: (done) => onProgress?.call(done, total),
      )) {
        if (cancel?.isCancelled == true) {
          throw const TransferCancelledException();
        }
        yield chunk;
      }
    } on SftpStatusError catch (e) {
      throw KelolaException(e.message.isEmpty ? e.toString() : e.message);
    } on SftpError catch (e) {
      throw KelolaException(e.message);
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> write(
    String path,
    Stream<List<int>> data, {
    void Function(int done)? onProgress,
    TransferCancel? cancel,
  }) {
    return _wrap(() async {
      final remote = await _sftp.open(
        path,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      try {
        final writer = remote.write(
          data.map((c) => c is Uint8List ? c : Uint8List.fromList(c)),
          onProgress: onProgress,
        );
        cancel?.addListener(() {
          writer.abort();
        });
        if (cancel?.isCancelled == true) {
          await writer.abort();
          throw const TransferCancelledException();
        }
        await writer.done;
        if (cancel?.isCancelled == true) {
          throw const TransferCancelledException();
        }
      } finally {
        await remote.close();
      }
    });
  }
}

Future<T> _wrap<T>(Future<T> Function() fn) async {
  try {
    return await fn();
  } on TransferCancelledException {
    rethrow;
  } on KelolaException {
    rethrow;
  } on SftpStatusError catch (e) {
    throw KelolaException(e.message.isEmpty ? e.toString() : e.message);
  } on SftpError catch (e) {
    throw KelolaException(e.message);
  }
}
