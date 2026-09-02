String shellSingleQuote(String value) {
  return "'${value.replaceAll("'", "'\\''")}'";
}

bool looksLikeSudoPasswordPrompt(String stderr) {
  final s = stderr.toLowerCase();
  return s.contains('a password is required') ||
      s.contains('a terminal is required') ||
      s.contains('no tty present') ||
      s.contains('no askpass program') ||
      s.contains('interactive authentication is required');
}
