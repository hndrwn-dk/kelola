abstract class AppLockPort {
  Future<bool> canAuthenticate();

  /// `true` unlocked. `false` user cancelled or failed.
  Future<bool> authenticate();

  Future<void> setRecentsSecure(bool secure);

  /// Hides the app's Recents preview without blocking screenshots.
  /// Android 13+; a no-op elsewhere.
  Future<void> setRecentsPreviewHidden(bool hidden);
}
