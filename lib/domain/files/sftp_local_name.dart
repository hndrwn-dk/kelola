import 'package:path/path.dart' as p;

/// Whether a server-supplied SFTP listing name is one plain file name.
///
/// The SFTP server picks `filename` in every listing reply, so a hostile host
/// can send `../kelola.sqlite` or `a/../../x`. Those names must never reach a
/// local path or a remote join: reject separators, NUL, `.`, `..` and empty.
bool isSafeSftpEntryName(String name) {
  if (name.isEmpty || name == '.' || name == '..') {
    return false;
  }
  return !name.contains('/') &&
      !name.contains('\\') &&
      !name.contains('\u0000');
}

/// Local path for [name] directly inside [dir], or throws [ArgumentError].
///
/// Callers write downloaded bytes here, so the result must stay inside [dir]
/// even if [isSafeSftpEntryName] were bypassed upstream.
String sftpLocalPathIn(String dir, String name) {
  if (!isSafeSftpEntryName(name)) {
    throw ArgumentError.value(name, 'name', 'unsafe SFTP file name');
  }
  final root = p.normalize(p.absolute(dir));
  final target = p.normalize(p.join(root, name));
  if (p.dirname(target) != root) {
    throw ArgumentError.value(name, 'name', 'unsafe SFTP file name');
  }
  return target;
}
