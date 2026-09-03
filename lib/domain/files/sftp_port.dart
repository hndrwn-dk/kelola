import 'package:kelola/domain/files/sftp_entry.dart';

class TransferCancel {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }
}

abstract class SftpPort {
  Future<String> absolute(String path);

  Future<List<SftpEntry>> listdir(String path);

  Future<SftpEntry> stat(String path);

  Future<void> mkdir(String path);

  Future<void> rename(String from, String to);

  Future<void> remove(String path);

  Future<void> rmdir(String path);

  Future<void> chmod(String path, int mode);

  Stream<List<int>> read(
    String path, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  });

  Future<void> write(
    String path,
    Stream<List<int>> data, {
    void Function(int done)? onProgress,
    TransferCancel? cancel,
  });
}
