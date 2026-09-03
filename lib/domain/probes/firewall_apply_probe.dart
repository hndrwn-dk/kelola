import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/firewall/firewall_parser.dart';
import 'package:kelola/domain/firewall/firewall_snapshot.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

/// Host-side 60s revert. [sh] runs as the SSH user (the probe already
/// executes in that shell). [sudo -n] is only the firewall binary.
/// Never [sudo sh] — that would be full root and cannot be passwordless.
String firewallScheduleRevert(String revertSudoCmd) {
  return '''
nohup sh -c ${shellSingleQuote('sleep 60; $revertSudoCmd')} >/dev/null 2>&1 &
rp=\$!
echo "---REVERT_PID---"
echo \$rp
''';
}

String firewallAfterApply() {
  return r'''
ec=$?
if [ $ec -ne 0 ]; then
  kill $rp 2>/dev/null || true
  exit $ec
fi
echo "---DONE---"
''';
}

class FirewallApplyProbe extends Probe<FirewallApplyResult> {
  const FirewallApplyProbe(this.change);

  final FirewallChange change;

  @override
  String get auditTitle => 'Applied firewall rule';

  @override
  String command(HostFacts facts) {
    if (facts.fw == FirewallBackend.iptables ||
        facts.fw == FirewallBackend.none) {
      return 'echo read-only; exit 1';
    }
    return switch (facts.fw) {
      FirewallBackend.firewalld => _firewalldApply(),
      FirewallBackend.ufw => _ufwApply(),
      FirewallBackend.nftables => _nftApply(),
      FirewallBackend.iptables => 'echo read-only; exit 1',
      FirewallBackend.none => 'echo read-only; exit 1',
    };
  }

  String _zoneFlag() {
    final z = change.zone;
    if (z == null || z.isEmpty) {
      return '';
    }
    return ' --zone=${shellSingleQuote(z)}';
  }

  String _firewalldApply() {
    final port = shellSingleQuote(change.port);
    final z = _zoneFlag();
    if (change.verb == FirewallVerb.addPort) {
      return '''
LC_ALL=C
sudo -n /usr/bin/firewall-cmd$z --add-port=$port --timeout=60
echo "---DONE---"
''';
    }
    return '''
LC_ALL=C
${firewallScheduleRevert('sudo -n /usr/bin/firewall-cmd$z --add-port=$port')}
sudo -n /usr/bin/firewall-cmd$z --remove-port=$port
${firewallAfterApply()}
''';
  }

  String _ufwApply() {
    final port = shellSingleQuote(change.port);
    if (change.verb == FirewallVerb.addPort) {
      return '''
LC_ALL=C
${firewallScheduleRevert('sudo -n /usr/sbin/ufw delete allow $port')}
sudo -n /usr/sbin/ufw allow $port
${firewallAfterApply()}
''';
    }
    return '''
LC_ALL=C
${firewallScheduleRevert('sudo -n /usr/sbin/ufw allow $port')}
sudo -n /usr/sbin/ufw delete allow $port
${firewallAfterApply()}
''';
  }

  String _nftApply() {
    final spec = change.port;
    final proto = spec.contains('/udp') ? 'udp' : 'tcp';
    final num = spec.split('/').first;
    if (change.verb == FirewallVerb.addPort) {
      final revert =
          'h=\$(sudo -n /usr/sbin/nft -a list chain inet filter input | grep kelola | grep "dport $num" | awk "{print \\\$NF; exit}"); '
          'sudo -n /usr/sbin/nft delete rule inet filter input handle \$h';
      return '''
LC_ALL=C
${firewallScheduleRevert(revert)}
sudo -n /usr/sbin/nft add rule inet filter input $proto dport $num accept comment kelola
echo "---JSON---"
sudo -n /usr/sbin/nft -j list chain inet filter input
${firewallAfterApply()}
''';
    }
    final handle = change.handle;
    if (handle == null || handle.isEmpty) {
      return 'echo missing-handle; exit 1';
    }
    return '''
LC_ALL=C
${firewallScheduleRevert('sudo -n /usr/sbin/nft add rule inet filter input $proto dport $num accept comment kelola')}
sudo -n /usr/sbin/nft delete rule inet filter input handle $handle
${firewallAfterApply()}
''';
  }

  @override
  FirewallApplyResult parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(
          kind: SudoHintKind.firewall,
          binary: '/usr/bin/firewall-cmd --add-port=${change.port}',
        ),
      );
    }
    if (stdout.contains('read-only')) {
      throw KelolaException('iptables is read-only in v1.');
    }
    if (stdout.contains('missing-handle')) {
      throw KelolaException(
        'Cannot remove this nftables rule without a handle.',
      );
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return FirewallApplyResult(
      change: change,
      revertPid: _pid(stdout),
      handle: _nftHandle(stdout),
    );
  }

  static int? _pid(String stdout) {
    const marker = '---REVERT_PID---';
    final i = stdout.indexOf(marker);
    if (i < 0) {
      return null;
    }
    final rest = stdout.substring(i + marker.length).trimLeft();
    return int.tryParse(rest.split('\n').first.trim());
  }

  static String? _nftHandle(String stdout) {
    const marker = '---JSON---';
    final i = stdout.indexOf(marker);
    if (i < 0) {
      return null;
    }
    final jsonText = stdout.substring(i + marker.length);
    final snap = const FirewallParser().parse(
      backend: FirewallBackend.nftables,
      stdout: jsonText,
    );
    for (final r in snap.rules.reversed) {
      if (r.handle != null && r.handle!.isNotEmpty) {
        return r.handle;
      }
    }
    return null;
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.destructive;

  @override
  Duration get timeout => const Duration(seconds: 30);
}

class FirewallRevertProbe extends Probe<String> {
  const FirewallRevertProbe(this.change);

  final FirewallChange change;

  @override
  String get auditTitle => 'Reverted firewall rule';

  @override
  String command(HostFacts facts) {
    final pid = change.revertPid;
    final kill = pid == null ? '' : 'kill $pid 2>/dev/null || true\n';
    return switch (facts.fw) {
      FirewallBackend.firewalld => _firewalld(kill),
      FirewallBackend.ufw => _ufw(kill),
      FirewallBackend.nftables => _nft(kill),
      FirewallBackend.iptables => 'echo read-only; exit 1',
      FirewallBackend.none => 'echo read-only; exit 1',
    };
  }

  String _zoneFlag() {
    final z = change.zone;
    if (z == null || z.isEmpty) {
      return '';
    }
    return ' --zone=${shellSingleQuote(z)}';
  }

  String _firewalld(String kill) {
    final port = shellSingleQuote(change.port);
    final z = _zoneFlag();
    final undo = change.verb == FirewallVerb.addPort
        ? 'sudo -n /usr/bin/firewall-cmd$z --remove-port=$port'
        : 'sudo -n /usr/bin/firewall-cmd$z --add-port=$port';
    return '''
LC_ALL=C
$kill$undo
echo reverted
''';
  }

  String _ufw(String kill) {
    final port = shellSingleQuote(change.port);
    final undo = change.verb == FirewallVerb.addPort
        ? 'sudo -n /usr/sbin/ufw delete allow $port'
        : 'sudo -n /usr/sbin/ufw allow $port';
    return '''
LC_ALL=C
$kill$undo
echo reverted
''';
  }

  String _nft(String kill) {
    final handle = change.handle;
    if (handle == null || handle.isEmpty) {
      return '''
LC_ALL=C
${kill}echo reverted
''';
    }
    return '''
LC_ALL=C
${kill}sudo -n /usr/sbin/nft delete rule inet filter input handle $handle
echo reverted
''';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(
          kind: SudoHintKind.firewall,
          binary: '/usr/bin/firewall-cmd --remove-port=${change.port}',
        ),
      );
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return 'reverted';
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.destructive;

  @override
  Duration get timeout => const Duration(seconds: 30);
}

class FirewallKeepProbe extends Probe<String> {
  const FirewallKeepProbe(this.change);

  final FirewallChange change;

  @override
  String get auditTitle => 'Kept firewall rule';

  @override
  String command(HostFacts facts) {
    final pid = change.revertPid;
    final kill = pid == null ? '' : 'kill $pid 2>/dev/null || true\n';
    if (facts.fw != FirewallBackend.firewalld) {
      return '''
LC_ALL=C
${kill}echo kept
''';
    }
    final port = shellSingleQuote(change.port);
    final z = change.zone == null || change.zone!.isEmpty
        ? ''
        : ' --zone=${shellSingleQuote(change.zone!)}';
    final perm = change.verb == FirewallVerb.addPort
        ? 'sudo -n /usr/bin/firewall-cmd$z --permanent --add-port=$port'
        : 'sudo -n /usr/bin/firewall-cmd$z --permanent --remove-port=$port';
    return '''
LC_ALL=C
$kill$perm
sudo -n /usr/bin/firewall-cmd --reload
echo kept
''';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(
          kind: SudoHintKind.firewall,
          binary:
              '/usr/bin/firewall-cmd --permanent --add-port=${change.port}',
        ),
      );
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return 'kept';
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.destructive;

  @override
  Duration get timeout => const Duration(seconds: 30);
}
