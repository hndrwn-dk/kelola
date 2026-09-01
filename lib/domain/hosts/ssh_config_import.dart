import 'package:kelola/domain/hosts/host.dart';

/// Parses OpenSSH config. Copies routing only — IdentityFile is ignored.
class SshConfigImporter {
  const SshConfigImporter();

  List<ImportedSshHost> parse(String source) {
    final hosts = <ImportedSshHost>[];
    String? alias;
    String? hostName;
    String? user;
    int port = 22;
    String? proxyJump;

    void flush() {
      final name = alias;
      if (name == null || name == '*') {
        return;
      }
      if (name.contains('*') || name.contains('?') || name.contains('!')) {
        return;
      }
      hosts.add(
        ImportedSshHost(
          alias: name,
          address: hostName ?? name,
          port: port,
          username: user ?? 'root',
          proxyJump: proxyJump,
        ),
      );
    }

    for (var raw in source.split('\n')) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final hash = line.indexOf('#');
      if (hash > 0) {
        line = line.substring(0, hash).trimRight();
      }
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }
      final key = parts.first.toLowerCase();
      final value = parts.sublist(1).join(' ');

      if (key == 'host') {
        flush();
        alias = parts[1];
        hostName = null;
        user = null;
        port = 22;
        proxyJump = null;
        continue;
      }

      switch (key) {
        case 'hostname':
          hostName = value;
        case 'user':
          user = value;
        case 'port':
          port = int.tryParse(value) ?? 22;
        case 'proxyjump':
          proxyJump = value.split(',').first.split('@').last.split(':').first;
        case 'identityfile':
        case 'identitiesonly':
        case 'certificatefile':
        case 'identityagent':
          break;
      }
    }
    flush();
    return hosts;
  }
}
