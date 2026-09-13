enum TunnelCloseReason {
  open,
  user,
  idle,
  termination,
  failed;

  String get value => name;

  static TunnelCloseReason? parse(String raw) {
    for (final reason in TunnelCloseReason.values) {
      if (reason.value == raw) {
        return reason;
      }
    }
    return null;
  }
}
