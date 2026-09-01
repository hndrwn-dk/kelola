class KelolaException implements Exception {
  KelolaException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HostKeyUnknownException implements Exception {
  HostKeyUnknownException({
    required this.hostId,
    required this.algorithm,
    required this.fingerprint,
  });

  final String hostId;
  final String algorithm;
  final String fingerprint;
}

class HostKeyMismatchException implements Exception {
  HostKeyMismatchException({
    required this.hostId,
    required this.pinnedFingerprint,
    required this.seenFingerprint,
    required this.algorithm,
  });

  final String hostId;
  final String pinnedFingerprint;
  final String seenFingerprint;
  final String algorithm;
}

class SshUnavailableException extends KelolaException {
  SshUnavailableException(super.message);
}

class RootLoginRejectedException extends KelolaException {
  RootLoginRejectedException()
      : super(
          'Kelola does not log in as root. Use a sudoer and keep PermitRootLogin off.',
        );
}

class SudoRequiredException extends KelolaException {
  SudoRequiredException()
      : super(
          'sudo asked for a password. Kelola uses sudo -n and will not hang. Add a NOPASSWD rule for the commands you want, or run them in a terminal.',
        );
}

class UnsupportedInitException extends KelolaException {
  UnsupportedInitException()
      : super(
          'This host is not systemd or OpenRC. Use a shell for services.',
        );
}
