import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';

Future<bool> confirmPackageApply(
  BuildContext context, {
  required String hostAlias,
  required List<String> names,
  required bool securityOnly,
  required bool rebootRequired,
}) {
  final n = names.length;
  final title = securityOnly
      ? 'Apply $n security updates?'
      : 'Apply $n updates?';
  final list = names.join('\n');
  final reboot = rebootRequired
      ? 'A reboot is already flagged on this host.\n\n'
      : '';
  return _sheet(
    context,
    title: title,
    consequence: 'This installs the listed packages on $hostAlias. Never auto-applied.',
    warning: '${reboot}Packages:\n$list',
    token: hostAlias,
  );
}

Future<bool> confirmFirewallChange(
  BuildContext context, {
  required String hostAlias,
  required String port,
  required bool lockout,
  required bool adding,
}) {
  final title = adding ? 'Allow $port?' : 'Remove $port?';
  if (lockout) {
    return _sheet(
      context,
      title: title,
      consequence:
          'This rule touches the SSH port and may make $hostAlias unreachable.',
      warning:
          'You will lose access immediately if the rule drops SSH. Recovery needs physical or console access. The host schedules a 60s rollback before the rule changes; Keep cancels that host timer. The phone is not the safety net.',
      token: hostAlias,
    );
  }
  return _sheet(
    context,
    title: title,
    consequence:
        'The host schedules a 60-second rollback before this rule changes. Keep cancels that host timer. If SSH drops, the host still reverts.',
    warning: adding
        ? 'Adds $port. Type $port to confirm.'
        : 'Removes $port. Type $port to confirm.',
    token: port,
  );
}

Future<bool> _sheet(
  BuildContext context, {
  required String title,
  required String consequence,
  required String warning,
  required String token,
}) async {
  var confirmed = false;
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: DestructiveConfirmSheet(
          title: title,
          consequence: consequence,
          warning: warning,
          confirmToken: token,
          onConfirmed: () => confirmed = true,
        ),
      );
    },
  );
  return confirmed;
}
