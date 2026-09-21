abstract class AppLockPort {
  Future<bool> canAuthenticate();

  /// `true` unlocked. `false` user cancelled or failed.
  Future<bool> authenticate();

  Future<void> setRecentsSecure(bool secure);
}
