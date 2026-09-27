import 'package:kelola/data/vault/vault_sftp_transport.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/probes/sftp_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class SftpVaultWriteProbe extends SftpProbe<void> {
  const SftpVaultWriteProbe(this.blob);

  final List<int> blob;

  @override
  String command(HostFacts facts) => 'sftp put ~/.kelola/vault.age';

  @override
  String get auditTitle => 'Vault remote write';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  Future<void> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) {
    return SftpVaultTransport(sftp).write(blob);
  }
}

class SftpVaultReadProbe extends SftpProbe<List<int>> {
  const SftpVaultReadProbe();

  @override
  String command(HostFacts facts) => 'sftp get ~/.kelola/vault.age';

  @override
  String get auditTitle => 'Vault remote read';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<List<int>> run(
    SftpPort sftp, {
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) {
    return SftpVaultTransport(sftp).read();
  }
}
