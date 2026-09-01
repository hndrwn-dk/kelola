import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/hosts/ssh_config_import.dart';

void main() {
  const importer = SshConfigImporter();

  test('imports Host blocks and ignores IdentityFile', () {
    const source = '''
Host nas-01
  HostName 192.168.1.24
  User hendra
  Port 22
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

Host web-prod
  HostName 10.0.4.11
  User deploy
  ProxyJump bastion
  IdentityFile /home/hendra/.ssh/prod

Host *
  User ignoreme
  IdentityFile ~/.ssh/id_rsa
''';
    final hosts = importer.parse(source);
    expect(hosts, hasLength(2));
    expect(hosts[0].alias, 'nas-01');
    expect(hosts[0].address, '192.168.1.24');
    expect(hosts[0].username, 'hendra');
    expect(hosts[1].alias, 'web-prod');
    expect(hosts[1].proxyJump, 'bastion');

    final dumped = hosts
        .map((h) => '${h.alias} ${h.address} ${h.username} ${h.proxyJump}')
        .join('\n');
    expect(dumped.contains('IdentityFile'), isFalse);
    expect(dumped.contains('id_ed25519'), isFalse);
    expect(dumped.contains('.ssh'), isFalse);
  });

  test('HostName defaults to the Host alias', () {
    final hosts = importer.parse('Host pi-dns\n  User hendra\n');
    expect(hosts.single.address, 'pi-dns');
    expect(hosts.single.port, 22);
  });
}
