import 'package:kelola/domain/files/sftp_path.dart';

bool isSshLockoutPath(String path) {
  final n = normalizeSftpPath(path.replaceAll('\\', '/'));
  if (sftpBasename(n) == 'authorized_keys') {
    return true;
  }
  final lower = n.toLowerCase();
  return lower == '/etc/ssh' || lower.startsWith('/etc/ssh/');
}
