String joinSftpPath(String base, String child) {
  final c = child.replaceAll('\\', '/');
  if (c.startsWith('/')) {
    return normalizeSftpPath(c);
  }
  final b = base.replaceAll('\\', '/');
  if (b.isEmpty || b == '.') {
    return normalizeSftpPath(c);
  }
  if (b.endsWith('/')) {
    return normalizeSftpPath('$b$c');
  }
  return normalizeSftpPath('$b/$c');
}

String normalizeSftpPath(String path) {
  final raw = path.replaceAll('\\', '/');
  final absolute = raw.startsWith('/');
  final parts = <String>[];
  for (final seg in raw.split('/')) {
    if (seg.isEmpty || seg == '.') {
      continue;
    }
    if (seg == '..') {
      if (parts.isNotEmpty) {
        parts.removeLast();
      }
      continue;
    }
    parts.add(seg);
  }
  if (!absolute) {
    return parts.isEmpty ? '.' : parts.join('/');
  }
  return '/${parts.join('/')}';
}

String sftpBasename(String path) {
  final n = normalizeSftpPath(path);
  if (n == '/') {
    return '/';
  }
  final i = n.lastIndexOf('/');
  if (i < 0) {
    return n;
  }
  return n.substring(i + 1);
}

String sftpParent(String path) {
  final n = normalizeSftpPath(path);
  if (n == '/') {
    return '/';
  }
  final i = n.lastIndexOf('/');
  if (i <= 0) {
    return '/';
  }
  return n.substring(0, i);
}

String sftpBakPath(String path) => '$path.bak';
