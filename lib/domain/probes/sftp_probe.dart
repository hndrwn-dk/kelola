import 'dart:io';

import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_entry.dart';
import 'package:kelola/domain/files/sftp_lockout.dart';
import 'package:kelola/domain/files/sftp_path.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

abstract class SftpProbe<T> extends Probe<T> {
  const SftpProbe();

  bool get isStream => false;

  @override
  T parse(String stdout, String stderr, int exitCode) {
    throw UnsupportedError('SFTP probes run via SftpPort');
  }

  Future<T> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  });
}

RiskLevel _mutateRisk(String path) {
  return isSshLockoutPath(path) ? RiskLevel.destructive : RiskLevel.mutate;
}

class SftpListProbe extends SftpProbe<SftpListing> {
  const SftpListProbe({required this.path});

  final String path;

  @override
  String command(HostFacts facts) => 'sftp ls $path';

  @override
  String get auditTitle => 'Listed $path';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<SftpListing> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) async {
    final abs = await sftp.absolute(path);
    final entries = await sftp.listdir(abs);
    return SftpListing(path: abs, entries: entries);
  }
}

class SftpDownloadProbe extends SftpProbe<int> {
  const SftpDownloadProbe({
    required this.remotePath,
    required this.localPath,
  });

  final String remotePath;
  final String localPath;

  @override
  bool get isStream => true;

  @override
  String command(HostFacts facts) => 'sftp get $remotePath';

  @override
  String get auditTitle => 'Downloaded ${sftpBasename(remotePath)}';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<int> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) async {
    final file = File(localPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    var total = 0;
    try {
      await for (final chunk in sftp.read(
        remotePath,
        onProgress: onProgress,
        cancel: cancel,
      )) {
        if (cancel?.isCancelled == true) {
          throw const TransferCancelledException();
        }
        sink.add(chunk);
        total += chunk.length;
      }
    } catch (e) {
      await sink.close();
      if (file.existsSync()) {
        file.deleteSync();
      }
      rethrow;
    }
    await sink.close();
    return total;
  }
}

class SftpUploadProbe extends SftpProbe<void> {
  const SftpUploadProbe({
    required this.localPath,
    required this.remotePath,
  });

  final String localPath;
  final String remotePath;

  @override
  bool get isStream => true;

  @override
  String command(HostFacts facts) => 'sftp put $remotePath';

  @override
  String get auditTitle => 'Uploaded ${sftpBasename(remotePath)}';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => _mutateRisk(remotePath);

  @override
  Future<void> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) {
    return sftp.write(
      remotePath,
      File(localPath).openRead(),
      onProgress: onProgress == null
          ? null
          : (done) => onProgress(done, null),
      cancel: cancel,
    );
  }
}

class SftpDeleteProbe extends SftpProbe<void> {
  const SftpDeleteProbe({required this.path});

  final String path;

  @override
  String command(HostFacts facts) => 'sftp rm $path';

  @override
  String get auditTitle => 'Deleted ${sftpBasename(path)}';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.destructive;

  @override
  Future<void> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) async {
    final entry = await sftp.stat(path);
    if (entry.isDirectory) {
      await sftp.rmdir(path);
    } else {
      await sftp.remove(path);
    }
  }
}

class SftpRenameProbe extends SftpProbe<void> {
  const SftpRenameProbe({required this.from, required this.to});

  final String from;
  final String to;

  @override
  String command(HostFacts facts) => 'sftp mv $from $to';

  @override
  String get auditTitle => 'Renamed ${sftpBasename(from)}';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => isSshLockoutPath(from) || isSshLockoutPath(to)
      ? RiskLevel.destructive
      : RiskLevel.mutate;

  @override
  Future<void> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) {
    return sftp.rename(from, to);
  }
}

class SftpChmodProbe extends SftpProbe<void> {
  const SftpChmodProbe({required this.path, required this.mode});

  final String path;
  final int mode;

  @override
  String command(HostFacts facts) =>
      'sftp chmod ${mode.toRadixString(8)} $path';

  @override
  String get auditTitle => 'Chmod ${sftpBasename(path)}';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => _mutateRisk(path);

  @override
  Future<void> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) {
    return sftp.chmod(path, mode);
  }
}

class SftpMkdirProbe extends SftpProbe<void> {
  const SftpMkdirProbe({required this.path});

  final String path;

  @override
  String command(HostFacts facts) => 'sftp mkdir $path';

  @override
  String get auditTitle => 'Created ${sftpBasename(path)}';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => _mutateRisk(path);

  @override
  Future<void> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) {
    return sftp.mkdir(path);
  }
}

class SftpSaveProbe extends SftpProbe<void> {
  const SftpSaveProbe({
    required this.remotePath,
    required this.originalLocalPath,
    required this.editedLocalPath,
  });

  final String remotePath;
  final String originalLocalPath;
  final String editedLocalPath;

  @override
  bool get isStream => true;

  @override
  String command(HostFacts facts) =>
      'sftp put ${sftpBakPath(remotePath)} ; sftp put $remotePath';

  @override
  String get auditTitle => 'Saved $remotePath';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => _mutateRisk(remotePath);

  @override
  Future<void> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) async {
    await sftp.write(
      sftpBakPath(remotePath),
      File(originalLocalPath).openRead(),
      onProgress: onProgress == null ? null : (done) => onProgress(done, null),
      cancel: cancel,
    );
    await sftp.write(
      remotePath,
      File(editedLocalPath).openRead(),
      onProgress: onProgress == null ? null : (done) => onProgress(done, null),
      cancel: cancel,
    );
  }
}
