import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/sftp_probe.dart';

void main() {
  test('audit titles and commands are sftp ops, not a shell', () {
    const list = SftpListProbe(path: '/etc');
    expect(list.auditTitle, 'Listed /etc');
    expect(list.command(HostFacts.undiscovered), 'sftp ls /etc');
    expect(list.needsSudo, isFalse);

    const del = SftpDeleteProbe(path: '/tmp/gone.txt');
    expect(del.auditTitle, 'Deleted gone.txt');
    expect(del.command(HostFacts.undiscovered), 'sftp rm /tmp/gone.txt');

    const save = SftpSaveProbe(
      remotePath: '/etc/nginx/nginx.conf',
      originalLocalPath: '/tmp/o',
      editedLocalPath: '/tmp/n',
    );
    expect(save.auditTitle, 'Saved /etc/nginx/nginx.conf');
    expect(save.command(HostFacts.undiscovered), contains('sftp put'));
    expect(save.isStream, isTrue);

    const get = SftpDownloadProbe(
      remotePath: '/var/log/syslog',
      localPath: '/tmp/syslog',
    );
    expect(get.isStream, isTrue);
    expect(const SftpListProbe(path: '/').isStream, isFalse);
  });
}
