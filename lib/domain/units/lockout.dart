import 'package:kelola/domain/units/service_unit.dart';

bool isSelfLockoutUnit(String name) {
  final n = name.trim().toLowerCase();
  const exact = {
    'ssh.service',
    'sshd.service',
    'dropbear.service',
    'networkmanager.service',
    'networkmanager-wait-online.service',
    'systemd-networkd.service',
    'systemd-networkd.socket',
    'networking.service',
    'network.service',
    'dhcpcd.service',
    'wicked.service',
  };
  if (exact.contains(n)) {
    return true;
  }
  if (n.startsWith('sshd@') || n.startsWith('ssh@')) {
    return true;
  }
  return false;
}

bool isDestructiveUnitAction(UnitVerb verb, String unit) {
  if (!isSelfLockoutUnit(unit)) {
    return false;
  }
  switch (verb) {
    case UnitVerb.stop:
    case UnitVerb.disable:
    case UnitVerb.restart:
      return true;
    case UnitVerb.start:
    case UnitVerb.reload:
    case UnitVerb.enable:
      return false;
  }
}
