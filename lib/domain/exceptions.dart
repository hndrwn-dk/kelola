import 'package:kelola/domain/sudo_hint.dart';

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
  SudoRequiredException([this.context = const SudoHintContext()])
      : super(_message(context));

  final SudoHintContext context;

  static const _lead =
      'sudo asked for a password. Kelola uses sudo -n and will not hang.';

  static String _message(SudoHintContext context) {
    if (context.kind == SudoHintKind.generic) {
      return '$_lead Add a NOPASSWD rule for the command that failed, or run it in a terminal.';
    }
    return '$_lead\n${SudoHintContext.wireMarker}\n${context.toWire()}';
  }
}

class UnsupportedInitException extends KelolaException {
  UnsupportedInitException()
      : super(
          'This host is not systemd or OpenRC. Use a shell for services.',
        );
}

class BinaryFileException extends KelolaException {
  BinaryFileException()
      : super('This file is binary. Download it instead of opening in the text editor.');
}

class FileTooLargeToEditException extends KelolaException {
  FileTooLargeToEditException()
      : super('File is too large to edit in Kelola. Download it instead.');
}

class SaveAbortedException extends KelolaException {
  SaveAbortedException() : super('Save cancelled');
}

class TransferCancelledException implements Exception {
  const TransferCancelledException();

  @override
  String toString() => 'Transfer cancelled';
}
