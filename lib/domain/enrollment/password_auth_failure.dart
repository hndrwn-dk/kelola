enum PasswordAuthFailureMode {
  rejected,
  passwordDisabled,
  connectionFailed,
}

class PasswordAuthFailure {
  const PasswordAuthFailure({
    required this.mode,
    required this.message,
    required this.offerRetry,
  });

  final PasswordAuthFailureMode mode;
  final String message;
  final bool offerRetry;
}

PasswordAuthFailure classifyPasswordAuthFailure({
  required Object error,
  required bool hostKeyVerified,
  required bool passwordMethodOffered,
}) {
  if (!hostKeyVerified) {
    return const PasswordAuthFailure(
      mode: PasswordAuthFailureMode.connectionFailed,
      message:
          'Could not connect to the host. Check network, host address, and SSH port. '
          'This is not a password error.',
      offerRetry: false,
    );
  }

  if (!passwordMethodOffered) {
    return const PasswordAuthFailure(
      mode: PasswordAuthFailureMode.passwordDisabled,
      message:
          'Password authentication is not available on this server. '
          'The server did not offer password login. Use the manual install path instead.',
      offerRetry: false,
    );
  }

  return const PasswordAuthFailure(
    mode: PasswordAuthFailureMode.rejected,
    message:
        'Authentication failed. Check the username and password, then try again '
        'or use the manual install path.',
    offerRetry: true,
  );
}
