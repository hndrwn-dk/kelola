import 'package:kelola/domain/firewall/firewall_snapshot.dart';

/// SSH-port lockout for firewall mutations. Same idea as unit/container lockout:
/// a rule that can drop the admin session is guarded.
bool firewallTouchesSsh({
  required String port,
  String? service,
  required int sshPort,
}) {
  final svc = (service ?? '').trim().toLowerCase();
  if (svc == 'ssh' || svc == 'openssh' || svc.contains('ssh')) {
    return true;
  }
  final n = portNumberOf(port);
  return n != null && n == sshPort;
}

bool isFirewallLockoutChange(FirewallChange change, {required int sshPort}) {
  return firewallTouchesSsh(port: change.port, sshPort: sshPort);
}

bool isFirewallLockoutRule(FirewallRule rule, {required int sshPort}) {
  return firewallTouchesSsh(
    port: rule.port ?? '',
    service: rule.service,
    sshPort: sshPort,
  );
}

int? portNumberOf(String port) {
  final spec = port.trim();
  if (spec.isEmpty) {
    return null;
  }
  return int.tryParse(spec.split('/').first.trim());
}

String normalizePortSpec(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) {
    return s;
  }
  if (RegExp(r'^\d+$').hasMatch(s)) {
    return '$s/tcp';
  }
  return s;
}
