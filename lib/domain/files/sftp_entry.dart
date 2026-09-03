import 'package:kelola/domain/files/chmod_mode.dart';

class SftpEntry {
  const SftpEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.owner,
    required this.group,
    required this.permissions,
    this.isSymlink = false,
    this.size,
    this.mtime,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final bool isSymlink;
  final int? size;
  final String owner;
  final String group;
  final String permissions;
  final DateTime? mtime;

  bool get isHidden =>
      name.startsWith('.') && name != '.' && name != '..';
}

SftpEntry sftpEntryFromListing({
  required String name,
  required String path,
  required String longname,
  required bool isDirectory,
  int? size,
  int? uid,
  int? gid,
  int? mode,
  int? mtimeSeconds,
  bool isSymlink = false,
}) {
  String? owner;
  String? group;
  String? perms;
  final parts = longname.trim().split(RegExp(r'\s+'));
  if (parts.length >= 4 && parts[0].length >= 10) {
    perms = parts[0].substring(1);
    owner = parts[2];
    group = parts[3];
  }
  final dir = isDirectory || longname.startsWith('d');
  return SftpEntry(
    name: name,
    path: path,
    isDirectory: dir,
    isSymlink: isSymlink || longname.startsWith('l'),
    size: size,
    owner: owner ?? (uid == null ? '?' : '$uid'),
    group: group ?? (gid == null ? '?' : '$gid'),
    permissions: perms ?? formatPermissionBits(mode ?? 0),
    mtime: mtimeSeconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(mtimeSeconds * 1000, isUtc: true),
  );
}

class SftpListing {
  const SftpListing({required this.path, required this.entries});

  final String path;
  final List<SftpEntry> entries;
}
