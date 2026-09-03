import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/files/sftp_lockout.dart';
import 'package:kelola/domain/probes/sftp_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  test('SSH config paths and authorized_keys trip lockout', () {
    expect(isSshLockoutPath('/etc/ssh/sshd_config'), isTrue);
    expect(isSshLockoutPath('/etc/ssh'), isTrue);
    expect(isSshLockoutPath('/etc/ssh/'), isTrue);
    expect(isSshLockoutPath('/home/u/.ssh/authorized_keys'), isTrue);
    expect(isSshLockoutPath('/etc/passwd'), isFalse);
    expect(isSshLockoutPath('/etc/ssh_config'), isFalse);
    expect(isSshLockoutPath('/tmp/authorized_keys'), isTrue);
  });

  test('browse and download stay read; mutate of lockout paths is destructive', () {
    expect(const SftpListProbe(path: '/etc/ssh').risk, RiskLevel.read);
    expect(
      const SftpDownloadProbe(remotePath: '/etc/ssh/sshd_config', localPath: '/tmp/x')
          .risk,
      RiskLevel.read,
    );
    expect(
      const SftpUploadProbe(localPath: '/tmp/x', remotePath: '/tmp/x').risk,
      RiskLevel.mutate,
    );
    expect(
      const SftpUploadProbe(localPath: '/tmp/x', remotePath: '/etc/ssh/sshd_config')
          .risk,
      RiskLevel.destructive,
    );
    expect(const SftpDeleteProbe(path: '/tmp/x').risk, RiskLevel.destructive);
    expect(
      const SftpRenameProbe(from: '/tmp/a', to: '/tmp/b').risk,
      RiskLevel.mutate,
    );
    expect(
      const SftpRenameProbe(from: '/etc/ssh/sshd_config', to: '/tmp/sshd_config')
          .risk,
      RiskLevel.destructive,
    );
    expect(
      const SftpChmodProbe(path: '/tmp/x', mode: 420).risk,
      RiskLevel.mutate,
    );
    expect(
      const SftpChmodProbe(path: '/etc/ssh/sshd_config', mode: 420).risk,
      RiskLevel.destructive,
    );
    expect(const SftpMkdirProbe(path: '/tmp/n').risk, RiskLevel.mutate);
    expect(const SftpMkdirProbe(path: '/etc/ssh/n').risk, RiskLevel.destructive);
  });
}
