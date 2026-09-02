class HostEditResult {
  const HostEditResult({
    required this.pinReset,
    required this.disconnectSession,
  });

  final bool pinReset;
  final bool disconnectSession;
}

abstract final class HostEditAudit {
  static String renamed(String alias) => 'Renamed host to $alias';
  static const changedAddress = 'Changed address';
  static const changedPort = 'Changed SSH port';
  static String changedJump(String? alias) =>
      alias == null ? 'Cleared jump host' : 'Changed jump host to $alias';
  static String changedUsername(String username) =>
      'Changed username to $username';
  static const setReadOnly = 'Set read-only';
  static const allowedWrites = 'Allowed writes';
}
