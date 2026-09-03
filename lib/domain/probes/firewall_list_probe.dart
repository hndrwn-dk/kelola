import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/firewall/firewall_parser.dart';
import 'package:kelola/domain/firewall/firewall_snapshot.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class FirewallListProbe extends Probe<FirewallSnapshot> {
  const FirewallListProbe();

  @override
  String get auditTitle => 'Listed firewall rules';

  @override
  String command(HostFacts facts) {
    final fw = facts.fw;
    if (fw == FirewallBackend.none) {
      return 'echo none; exit 1';
    }
    final body = switch (fw) {
      FirewallBackend.firewalld => '''
echo "---DEFAULT---"
sudo -n /usr/bin/firewall-cmd --get-default-zone
echo "---LIST---"
sudo -n /usr/bin/firewall-cmd --list-all
''',
      FirewallBackend.ufw => 'sudo -n /usr/sbin/ufw status verbose',
      FirewallBackend.nftables => 'sudo -n /usr/sbin/nft -j list ruleset',
      FirewallBackend.iptables => 'sudo -n /usr/sbin/iptables-save',
      FirewallBackend.none => 'echo none; exit 1',
    };
    return '''
LC_ALL=C
echo "---FW---"
echo ${fw.name}
$body
''';
  }

  @override
  FirewallSnapshot parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(
          kind: SudoHintKind.firewall,
          binary: _binaryFrom(stdout),
        ),
      );
    }
    if (exitCode != 0 && stdout.trim() == 'none') {
      throw KelolaException('No firewall backend on this host.');
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    final backend = _fwFrom(stdout);
    return const FirewallParser().parse(backend: backend, stdout: stdout);
  }

  static FirewallBackend _fwFrom(String stdout) {
    const marker = '---FW---';
    final i = stdout.indexOf(marker);
    if (i >= 0) {
      final rest = stdout.substring(i + marker.length).trimLeft();
      final line = rest.split('\n').first.trim();
      for (final v in FirewallBackend.values) {
        if (v.name == line) {
          return v;
        }
      }
    }
    return FirewallBackend.none;
  }

  static String _binaryFrom(String stdout) {
    final fw = _fwFrom(stdout);
    return switch (fw) {
      FirewallBackend.firewalld => '/usr/bin/firewall-cmd --list-all',
      FirewallBackend.ufw => '/usr/sbin/ufw status verbose',
      FirewallBackend.nftables => '/usr/sbin/nft -j list ruleset',
      FirewallBackend.iptables => '/usr/sbin/iptables-save',
      FirewallBackend.none => '/usr/bin/firewall-cmd --list-all',
    };
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 20);
}
