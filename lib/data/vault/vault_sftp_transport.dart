import 'dart:convert';

import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/vault/vault_transport.dart';

class SftpVaultTransport implements VaultTransport {
  SftpVaultTransport(this._sftp);

  final SftpPort _sftp;

  @override
  VaultTransportKind get kind => VaultTransportKind.sftp;

  Future<String> get _path async {
    final home = await _sftp.absolute('~');
    final dir = '$home/.kelola';
    return '$dir/vault.age';
  }

  @override
  Future<void> write(List<int> blob) async {
    final path = await _path;
    final dir = path.substring(0, path.lastIndexOf('/'));
    try {
      await _sftp.stat(dir);
    } catch (_) {
      await _sftp.mkdir(dir);
    }
    await _sftp.write(path, Stream<List<int>>.value(blob));
  }

  @override
  Future<List<int>> read() async {
    final chunks = <int>[];
    await for (final part in _sftp.read(await _path)) {
      chunks.addAll(part);
    }
    return chunks;
  }
}

List<int> vaultBlobBytes(String sealed) => utf8.encode(sealed);

String vaultBlobString(List<int> bytes) => utf8.decode(bytes);
