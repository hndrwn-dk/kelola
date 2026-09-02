import 'package:kelola/domain/exceptions.dart';

const sudoRequiredTitle = 'sudo needs a password';

const sudoMutateWillFail =
    '$sudoRequiredTitle — mutate actions will fail';

const sudoRequiredBody =
    'This host\'s sudo asks for a password, so mutate actions will fail. '
    'Kelola never prompts for a sudo password. Add a NOPASSWD sudoers entry '
    'for the commands below, or a polkit rule that lets this user run them '
    'without a password.';

const kelolaSudoersCommands = <String>[
  '/usr/sbin/reboot',
  '/usr/sbin/poweroff',
  '/usr/bin/systemctl',
  '/usr/bin/kill',
  '/bin/sh',
  '/usr/bin/docker',
];

String kelolaSudoersLine({String user = 'YOURUSER'}) {
  return '$user ALL=(root) NOPASSWD: ${kelolaSudoersCommands.join(', ')}';
}

bool looksLikeSudoRequired(Object error) {
  if (error is SudoRequiredException) {
    return true;
  }
  final s = error.toString().toLowerCase();
  if (!s.contains('sudo')) {
    return false;
  }
  return s.contains('password') ||
      s.contains('interactive authentication') ||
      s.contains('no tty') ||
      s.contains('askpass') ||
      s.contains('a terminal is required');
}
