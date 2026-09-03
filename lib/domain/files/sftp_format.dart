String formatSftpSize(int? bytes) {
  if (bytes == null) {
    return '';
  }
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}

String formatSftpMtime(DateTime? mtime) {
  if (mtime == null) {
    return '';
  }
  final u = mtime.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}';
}

String sftpRowMeta({
  required String permissions,
  required String owner,
  int? size,
  DateTime? mtime,
  required bool isDirectory,
}) {
  final parts = <String>[
    permissions,
    owner,
    if (!isDirectory && size != null) formatSftpSize(size),
    if (mtime != null) formatSftpMtime(mtime),
  ];
  return parts.join(' · ');
}
