import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudoers_install_script.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';
import 'package:kelola/domain/units/shell_quote.dart';

/// Every sudoers file Kelola writes, and nothing else: the Enable file, the
/// old per-action grant M52d folds in, and the web lens read rules. Host
/// details lists and removes lines in these only, by exact path; never a
/// glob over `/etc/sudoers.d`.
const kelolaOwnedSudoersFiles = [
  kelolaSudoersPath,
  kelolaUnitSudoersPath,
  kelolaWebSudoersPath,
];

/// Where the app lists and removes these lines; grant copy points here
/// instead of asking for a hand edit.
const kelolaSudoRulesPlace = 'Host details → Kelola sudo rules';

/// Whether [line] is a sudoers rule (not blank, not a comment). `#include`,
/// `#includedir` and `@…` lines are directives, so they count as content: a
/// file holding one is never deleted as empty.
bool isSudoersRuleLine(String line) {
  final l = line.trimLeft();
  if (l.isEmpty) return false;
  if (l.startsWith('#include')) return true;
  return !l.startsWith('#');
}

/// The command of a file line (`<user> ALL=(root) NOPASSWD: <cmd>`), or
/// [line] itself when it is a command already.
String kelolaSudoRuleCommand(String line) {
  const tag = ' NOPASSWD: ';
  final at = line.indexOf(tag);
  return at < 0 ? line.trim() : line.substring(at + tag.length).trim();
}

/// The NOPASSWD commands a `sudo -n -l` listing grants, from classic sudo or
/// sudo-rs: listing escapes removed ([normalizeSudoRule]), and a rule that
/// lists several commands (`/a, /b`) split into one each. Rules that need a
/// password are left out.
List<String> parseSudoListingCommands(String listing) {
  final out = <String>[];
  for (final line in const LineSplitter().convert(listing)) {
    const tag = 'NOPASSWD:';
    final at = line.indexOf(tag);
    if (at < 0) continue;
    final rest = line.substring(at + tag.length).trim();
    for (final part in rest.split(RegExp(r', (?=/)'))) {
      final cmd = normalizeSudoRule(part).trim();
      if (cmd.isNotEmpty) out.add(cmd);
    }
  }
  return out;
}

const _kelolaBinaryNames = {
  'dnf',
  'yum',
  'apt-get',
  'zypper',
  'apk',
  'pacman',
  'firewall-cmd',
  'ufw',
  'nft',
  'iptables-save',
  'reboot',
  'poweroff',
  'systemctl',
  'kill',
  'docker',
  'sysctl',
  'test',
  'tail',
  'openssl',
  'nginx',
  'apachectl',
  'apache2ctl',
  'httpd',
};

/// Whether [command] runs a binary Kelola writes rules for, from a system
/// directory. A listing does not say which file a rule came from, so this is
/// how the read-only fallback picks Kelola's lines.
bool isKelolaSudoCommand(String command) {
  // An old refusal (`!<bin>`) names the binary after the `!`.
  final c = command.startsWith('!') ? command.substring(1) : command;
  final bin = c.split(' ').first;
  final i = bin.lastIndexOf('/');
  if (i <= 0) return false;
  return webGrantSystemDirs.contains(bin.substring(0, i)) &&
      _kelolaBinaryNames.contains(bin.substring(i + 1));
}

/// What a Kelola rule allows, in plain words ("Reload nginx.service").
/// Takes a file line or a command; host text in it (unit names, paths) is
/// only repeated. Anything unknown reads as "Run `command` as root".
String describeKelolaSudoRule(String lineOrCommand) {
  final cmd = normalizeSudoRule(kelolaSudoRuleCommand(lineOrCommand));
  if (cmd == 'ALL') return 'Run any command as root';
  // Shapes earlier versions wrote ([kelolaSudoRulesOutdated]): a refusal,
  // which in this file also denies the login's own password sudo; a bare
  // binary or a trailing `*`, which take any arguments.
  // "(old rule)" only for Kelola's own binaries.
  final old = isKelolaSudoCommand(cmd) ? ' (old rule)' : '';
  if (cmd.startsWith('!')) {
    return 'Blocks ${cmd.substring(1)} for this login, even with a '
        'password$old';
  }
  if (cmd.startsWith('/') && !cmd.contains(' ')) {
    return 'Run $cmd with any arguments as root$old';
  }
  if (cmd.endsWith(' *')) {
    return 'Run ${cmd.substring(0, cmd.length - 2)} with any arguments as '
        'root$old';
  }
  final sp = cmd.indexOf(' ');
  final bin = sp < 0 ? cmd : cmd.substring(0, sp);
  final args = sp < 0 ? '' : cmd.substring(sp + 1);
  final name = bin.substring(bin.lastIndexOf('/') + 1);
  final words = args.split(' ');
  final other = 'Run $cmd as root';
  String last() => words.last;
  switch (name) {
    case 'systemctl':
      if (args.startsWith('^')) {
        return 'Start, stop, restart or reload any service (old rule)';
      }
      if (words.length == 2 && kelolaUnitLifecycleVerbs.contains(words[0])) {
        final verb = words[0];
        return '${verb[0].toUpperCase()}${verb.substring(1)} ${words[1]}';
      }
      return other;
    case 'reboot':
      return 'Reboot the host';
    case 'poweroff':
      return 'Power off the host';
    case 'sysctl':
      return args == '-w vm.drop_caches=3' ? 'Flush caches' : other;
    case 'kill':
      return 'Send TERM or KILL to a process';
    case 'docker':
      if (args == 'info') return 'Read Docker status';
      if (args.startsWith('ps ')) return 'List Docker containers';
      if (args.contains('logs')) return "Read a container's recent logs";
      return other;
    case 'dnf' || 'yum' || 'zypper' || 'apt-get' || 'apk' || 'pacman':
      if (args.startsWith('^')) return 'Upgrade one package';
      if (args.contains('check-update')) return 'Check for package updates';
      if (args.contains('updateinfo')) return 'List security updates';
      if (args.contains('--security') ||
          args.contains('security.sources.list') ||
          args.contains('--category security')) {
        return 'Install security updates';
      }
      return 'Upgrade all packages';
    case 'firewall-cmd':
      if (args == '--reload') return 'Reload the firewall';
      if (args.startsWith('^')) return 'Open or close a firewall port';
      return 'Read firewall rules';
    case 'ufw':
      return args.startsWith('^')
          ? 'Open or close a firewall port'
          : 'Read firewall rules';
    case 'nft':
      if (args.startsWith('^add')) return 'Open a firewall port';
      if (args.startsWith('^delete')) return 'Close a firewall port';
      return 'Read firewall rules';
    case 'iptables-save':
      return 'Read firewall rules';
    case 'test':
      return words.length == 2 && words[0] == '-r'
          ? 'Check ${words[1]} is readable'
          : other;
    case 'tail':
      if (words.length == 4 && words[1] == '0' && words[2] == '-F') {
        return 'Follow ${last()}';
      }
      if (words.length == 3 && words[0] == '-n') {
        return 'Read the last ${words[1]} lines of ${last()}';
      }
      return other;
    case 'nginx':
      if (args == '-t') return 'Test the nginx config';
      if (args == '-T') return 'Print the nginx config';
      return other;
    case 'apachectl' || 'apache2ctl' || 'httpd':
      if (args == '-t') return 'Test the Apache config';
      if (args == '-S') return 'Print the Apache vhosts';
      return other;
    case 'openssl':
      final i = words.indexOf('-in');
      return i >= 0 && i == words.length - 2
          ? 'Read certificate ${last()}'
          : other;
  }
  return other;
}

enum KelolaSudoFileState {
  present,
  absent,

  /// `/etc/sudoers.d` cannot be searched by the login, so whether the file
  /// is there is not known without the password.
  unknown,
}

/// One of [kelolaOwnedSudoersFiles] as the host showed it.
class KelolaSudoFile {
  const KelolaSudoFile({required this.path, required this.state, this.lines});

  final String path;
  final KelolaSudoFileState state;

  /// Its rule lines ([isSudoersRuleLine]), verbatim; null when the file could
  /// not be read without the password.
  final List<String>? lines;

  /// `kelola-web`: what a whole-file removal asks the user to type.
  String get name => path.substring(path.lastIndexOf('/') + 1);
}

/// What host details shows under "Kelola sudo rules".
class KelolaSudoFiles {
  const KelolaSudoFiles({required this.files, required this.listed});

  /// In [kelolaOwnedSudoersFiles] order, each at most once.
  final List<KelolaSudoFile> files;

  /// `sudo -n -l`'s NOPASSWD commands ([parseSudoListingCommands]).
  final List<String> listed;

  /// The files that are (or may be) there.
  List<KelolaSudoFile> get shown => [
    for (final f in files)
      if (f.state != KelolaSudoFileState.absent) f,
  ];

  /// Some file's contents need the sudo password.
  bool get contentsNeedPassword => shown.any((f) => f.lines == null);

  /// Listed commands that look like Kelola's ([isKelolaSudoCommand]), for
  /// when the files themselves cannot be read.
  List<String> get listedKelola => [
    for (final c in listed)
      if (isKelolaSudoCommand(c)) c,
  ];
}

const _kfile = '---KFILE---';
const _klist = '---LIST---';

/// Reads [kelolaOwnedSudoersFiles] and `sudo -n -l` for Host details.
///
/// Without the password: each file is read as the login, then with
/// `sudo -n cat` (a login with passwordless root reads it), else only its
/// presence is reported; `sudo -n -l` shows what is granted either way.
/// [withPassword] reads the files with the sudo password (stdin, one line).
/// Read-only either way: it never writes.
///
/// Host output is printed with a `|` prefix, so it cannot forge the
/// script's `---KFILE---` / `@key=value` lines; the parser also only takes
/// the three known paths.
///
/// [sudoersDir] exists for tests only (stub trees); the reported paths are
/// always [kelolaOwnedSudoersFiles].
class KelolaSudoFilesProbe extends Probe<KelolaSudoFiles> {
  const KelolaSudoFilesProbe({
    this.withPassword = false,
    @visibleForTesting this.sudoersDir = '/etc/sudoers.d',
  });

  final bool withPassword;
  final String sudoersDir;

  @override
  String get auditTitle => withPassword
      ? 'Read Kelola sudo files with the sudo password'
      : 'Read Kelola sudo rules';

  @override
  String command(HostFacts facts) {
    const pw = "printf '%s\\n' \"\$SUDO_PASS\" | sudo -S -p ''";
    final b = StringBuffer();
    if (withPassword) {
      b
        ..writeln('IFS= read -r SUDO_PASS || true')
        ..writeln(
          "if ! $pw true 2>/dev/null; then echo '@auth=fail'; "
          'unset SUDO_PASS; exit 4; fi',
        );
    }
    final dir = shellSingleQuote(sudoersDir);
    for (final path in kelolaOwnedSudoersFiles) {
      final f = shellSingleQuote(
        '$sudoersDir/${path.substring(path.lastIndexOf('/') + 1)}',
      );
      b
        ..writeln("echo '$_kfile'")
        ..writeln("echo '@path=$path'");
      if (withPassword) {
        b
          ..writeln('if c=\$($pw cat -- $f 2>/dev/null); then')
          ..writeln("  echo '@state=present'; echo '@read=1'")
          ..writeln("  printf '%s\\n' \"\$c\" | sed 's/^/|/'")
          ..writeln('elif $pw test -e $f 2>/dev/null; then')
          ..writeln("  echo '@state=present'; echo '@read=0'")
          ..writeln('else')
          ..writeln("  echo '@state=absent'; echo '@read=0'")
          ..writeln('fi');
      } else {
        b
          ..writeln(
            'if c=\$(cat -- $f 2>/dev/null) || '
            'c=\$(sudo -n cat -- $f 2>/dev/null); then',
          )
          ..writeln("  echo '@state=present'; echo '@read=1'")
          ..writeln("  printf '%s\\n' \"\$c\" | sed 's/^/|/'")
          ..writeln('elif [ -e $f ] || [ -L $f ]; then')
          ..writeln("  echo '@state=present'; echo '@read=0'")
          ..writeln('elif [ -x $dir ]; then')
          ..writeln("  echo '@state=absent'; echo '@read=0'")
          ..writeln('else')
          ..writeln("  echo '@state=unknown'; echo '@read=0'")
          ..writeln('fi');
      }
    }
    b
      ..writeln("echo '$_klist'")
      ..writeln("LC_ALL=C sudo -n -l 2>/dev/null | sed 's/^/|/'");
    if (withPassword) b.writeln('unset SUDO_PASS');
    return b.toString();
  }

  @override
  KelolaSudoFiles parse(String stdout, String stderr, int exitCode) {
    final lines = const LineSplitter().convert(stdout);
    if (withPassword && lines.contains('@auth=fail')) {
      throw KelolaException('The sudo password was not accepted.');
    }
    final byPath = <String, KelolaSudoFile>{};
    final listed = <String>[];
    String? path;
    String? state;
    String? read;
    var data = <String>[];
    var inList = false;
    void flush() {
      final p = path;
      if (p != null &&
          kelolaOwnedSudoersFiles.contains(p) &&
          !byPath.containsKey(p)) {
        final s = switch (state) {
          'present' => KelolaSudoFileState.present,
          'absent' => KelolaSudoFileState.absent,
          _ => KelolaSudoFileState.unknown,
        };
        byPath[p] = KelolaSudoFile(
          path: p,
          state: s,
          lines: s == KelolaSudoFileState.present && read == '1'
              ? List.unmodifiable(data.where(isSudoersRuleLine))
              : null,
        );
      }
      path = null;
      state = null;
      read = null;
      data = <String>[];
    }

    for (final l in lines) {
      if (l == _kfile) {
        flush();
        inList = false;
        path = '';
        continue;
      }
      if (l == _klist) {
        flush();
        inList = true;
        continue;
      }
      if (inList) {
        if (l.startsWith('|')) listed.add(l.substring(1));
        continue;
      }
      if (path == null) continue;
      if (l.startsWith('|')) {
        data.add(l.substring(1));
      } else if (l.startsWith('@path=')) {
        path = l.substring('@path='.length);
      } else if (l.startsWith('@state=')) {
        state = l.substring('@state='.length);
      } else if (l.startsWith('@read=')) {
        read = l.substring('@read='.length);
      }
    }
    flush();
    return KelolaSudoFiles(
      files: [
        for (final p in kelolaOwnedSudoersFiles) ?byPath[p],
      ],
      listed: parseSudoListingCommands(listed.join('\n')),
    );
  }

  @override
  bool get needsSudo => withPassword;

  @override
  RiskLevel get risk => RiskLevel.read;
}

/// What Host details asks to remove: one exact [line] of [path], or the
/// whole file when [line] is null.
typedef KelolaSudoRemoval = ({String path, String? line});

const kelolaSudoRemoveOkMarker = 'KELOLA_SUDO_REMOVE_OK';

/// The file was already gone; nothing was changed.
const kelolaSudoRemoveGoneMarker = 'KELOLA_SUDO_REMOVE_GONE';

/// The line was not in the file; nothing was changed.
const kelolaSudoRemoveMissingMarker = 'KELOLA_SUDO_REMOVE_MISSING';

/// The path is a symlink; nothing was changed (Kelola never writes one).
const kelolaSudoRemoveLinkMarker = 'KELOLA_SUDO_REMOVE_LINK';

class KelolaSudoRemoveResult {
  const KelolaSudoRemoveResult({required this.deleted});

  /// The file is gone (removed whole, or its last rule line was).
  final bool deleted;
}

/// Removes one exact [line] from, or (with [line] null) the whole of, one of
/// [kelolaOwnedSudoersFiles]. Destructive: the caller asks for presence.
///
/// Same write path as the grants: the sudo password on stdin (one line),
/// a temp copy edited with `grep -vxF`, `visudo -c -f` on the result, then
/// `install -o root -g root -m 0440`, then checked on the host. Removing the
/// last rule line ([isSudoersRuleLine]) deletes the file instead. Refuses a
/// symlink in the file's place. A failed visudo installs nothing.
class KelolaSudoRemoveProbe extends Probe<KelolaSudoRemoveResult> {
  KelolaSudoRemoveProbe({required this.path, this.line}) {
    if (!kelolaOwnedSudoersFiles.contains(path)) {
      throw ArgumentError.value(path, 'path', 'not a Kelola sudoers file');
    }
    final l = line;
    if (l != null &&
        (l.contains('\n') || l.contains('\r') || !isSudoersRuleLine(l))) {
      throw ArgumentError.value(l, 'line');
    }
  }

  final String path;

  /// Exact, as read from the file; null removes the whole file.
  final String? line;

  String get _name => path.substring(path.lastIndexOf('/') + 1);

  @override
  String get auditTitle =>
      line == null ? 'Removed $path' : 'Removed a line from $path';

  @override
  String auditCommand(HostFacts facts) => line == null
      ? 'kelola-sudoers-remove $path'
      : 'kelola-sudoers-remove $path line=${kelolaSudoRuleCommand(line!)}';

  @override
  String command(HostFacts facts) {
    const s = "printf '%s\\n' \"\$SUDO_PASS\" | sudo -S -p ''";
    final p = shellSingleQuote(path);
    final mode = shellSingleQuote(kelolaSudoersMode);
    final b = StringBuffer()
      ..writeln('set -eu')
      ..writeln('IFS= read -r SUDO_PASS || true')
      ..writeln(r'TMP=$(mktemp)')
      ..writeln(r'NEW=$(mktemp)')
      ..writeln(r'''trap 'rm -f "$TMP" "$NEW"' EXIT''')
      // A wrong password stops here, before anything is read or written.
      ..writeln('$s true')
      ..writeln(
        "if $s test -L $p; then printf '%s\\n' '$kelolaSudoRemoveLinkMarker'; "
        'exit 3; fi',
      )
      ..writeln(
        "if ! $s test -f $p; then printf '%s\\n' '$kelolaSudoRemoveGoneMarker'; "
        'exit 0; fi',
      );
    String deleted() =>
        '$s rm -f -- $p\n'
        'if $s test -e $p; then exit 1; fi\n'
        "printf '%s\\n' '$kelolaSudoRemoveOkMarker' '@deleted=1'\n";
    final l = line;
    if (l == null) {
      b.write(deleted());
    } else {
      final b64 = base64Encode(utf8.encode(l));
      b
        ..writeln("L=\$(printf '%s' '$b64' | base64 -d)")
        ..writeln('$s cat -- $p > "\$TMP"')
        ..writeln(
          'if ! grep -qxF -- "\$L" "\$TMP"; then '
          "printf '%s\\n' '$kelolaSudoRemoveMissingMarker'; exit 3; fi",
        )
        ..writeln(r'{ grep -vxF -- "$L" "$TMP" || true; } > "$NEW"')
        ..writeln('LEFT=0')
        ..writeln(r'while IFS= read -r l || [ -n "$l" ]; do')
        ..writeln(
          r'''  case "$l" in '#include'*|'@'*) LEFT=1 ;; '#'*) ;; '''
          r'*[![:space:]]*) LEFT=1 ;; esac',
        )
        ..writeln(r'done < "$NEW"')
        ..writeln(r'if [ "$LEFT" = 0 ]; then')
        ..write(deleted())
        ..writeln('  exit 0')
        ..writeln('fi')
        ..writeln('$s visudo -c -f "\$NEW"')
        ..writeln('$s install -o root -g root -m $mode "\$NEW" $p')
        ..writeln('if $s grep -qxF -- "\$L" $p; then exit 1; fi')
        ..writeln("printf '%s\\n' '$kelolaSudoRemoveOkMarker' '@deleted=0'");
    }
    b.writeln('unset SUDO_PASS');
    return b.toString();
  }

  @override
  KelolaSudoRemoveResult parse(String stdout, String stderr, int exitCode) {
    final lines = const LineSplitter().convert(stdout).map((l) => l.trim());
    if (lines.contains(kelolaSudoRemoveLinkMarker)) {
      throw KelolaException(
        '$path is a symlink, which Kelola never writes. Nothing was changed; '
        'check it on the host.',
      );
    }
    if (lines.contains(kelolaSudoRemoveMissingMarker)) {
      throw KelolaException(
        'That line is no longer in $_name. Nothing was changed.',
      );
    }
    if (exitCode == 0 && lines.contains(kelolaSudoRemoveGoneMarker)) {
      return const KelolaSudoRemoveResult(deleted: true);
    }
    if (exitCode == 0 && lines.contains(kelolaSudoRemoveOkMarker)) {
      return KelolaSudoRemoveResult(deleted: lines.contains('@deleted=1'));
    }
    final err = stderr.trim();
    throw KelolaException(
      err.isEmpty ? 'Could not change $_name. Nothing was changed.' : err,
    );
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.destructive;

  @override
  Duration get timeout => const Duration(seconds: 45);
}
