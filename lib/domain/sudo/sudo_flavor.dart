/// Which sudo a host runs, read from the first line of `sudo -V`.
///
/// This decides what Kelola can write to its sudoers file. sudo-rs rejects a
/// whole file over one regex or one wildcard inside an argument, and classic
/// sudo before 1.9.10 reads `^…$` as literal text.
sealed class SudoFlavor {
  const SudoFlavor();

  /// Whether a command argument can be an anchored regex (`^…$`).
  bool get supportsArgRegex => false;
}

final class ClassicSudo extends SudoFlavor {
  const ClassicSudo(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  @override
  bool get supportsArgRegex =>
      major > 1 || (major == 1 && (minor > 9 || (minor == 9 && patch >= 10)));
}

final class SudoRs extends SudoFlavor {
  const SudoRs(this.version);

  final String version;
}

final class UnknownSudo extends SudoFlavor {
  const UnknownSudo();
}

final _classicLine = RegExp(r'^Sudo version (\d+)\.(\d+)\.(\d+)');
final _sudoRsLine = RegExp(r'^sudo-rs\s+(\S+)');

/// [output] is `sudo -V`: `Sudo version 1.9.15p5` or `sudo-rs 0.2.13-…`.
/// Anything else is [UnknownSudo], which never gets regex rules.
SudoFlavor parseSudoFlavor(String output) {
  final line = output.trimLeft().split('\n').first.trim();
  final rs = _sudoRsLine.firstMatch(line);
  if (rs != null) {
    return SudoRs(rs.group(1)!);
  }
  final classic = _classicLine.firstMatch(line);
  if (classic == null) {
    return const UnknownSudo();
  }
  final major = int.tryParse(classic.group(1)!);
  final minor = int.tryParse(classic.group(2)!);
  final patch = int.tryParse(classic.group(3)!);
  if (major == null || minor == null || patch == null) {
    return const UnknownSudo();
  }
  return ClassicSudo(major, minor, patch);
}
