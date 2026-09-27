enum VaultTransportKind { file, lan, sftp }

const String kVaultSftpRelPath = '.kelola/vault.age';

bool vaultTransportRequiresUnlock(VaultTransportKind kind) {
  return kind != VaultTransportKind.file;
}

abstract class VaultTransport {
  VaultTransportKind get kind;

  Future<void> write(List<int> blob);

  Future<List<int>> read();
}
