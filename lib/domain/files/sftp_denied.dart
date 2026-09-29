import 'package:kelola/domain/files/sftp_path.dart';

class SftpDeniedCopy {
  const SftpDeniedCopy({
    required this.title,
    required this.body,
    required this.snippet,
  });

  final String title;
  final String body;
  final String snippet;
}

bool looksLikeSftpPermissionDenied(String message) {
  final hay = message.toLowerCase();
  return hay.contains('permission denied') ||
      hay.contains('code 3') ||
      hay.contains('ssh_fx_permission_denied');
}

bool sftpOutsideLoginHome(String path, String username) {
  final user = username.trim();
  if (user.isEmpty) {
    return false;
  }
  final n = normalizeSftpPath(path);
  final home = normalizeSftpPath('/home/$user');
  return n != home && !n.startsWith('$home/');
}

String sftpOutsideHomeWarning({
  required String username,
  required String path,
}) {
  final user = username.trim().isEmpty ? 'this user' : username.trim();
  return 'Logged in as $user. $path is outside that home directory and may not be writable.';
}

SftpDeniedCopy sftpDeniedCopy({
  required String message,
  required String path,
  required String username,
}) {
  final user = username.trim().isEmpty ? 'this user' : username.trim();
  if (looksLikeSftpPermissionDenied(message)) {
    return SftpDeniedCopy(
      title: 'Permission denied',
      body:
          'Logged in as $user. You can write in directories you own. This path is not writable for that login.',
      snippet: path,
    );
  }
  return SftpDeniedCopy(
    title: 'Transfer failed',
    body: 'The host refused this write.',
    snippet: message.trim().isEmpty ? path : message.trim(),
  );
}
