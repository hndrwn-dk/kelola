import 'package:kelola/domain/files/sftp_entry.dart';

class SftpListView {
  const SftpListView({
    required this.rows,
    required this.hiddenCount,
    this.emptyCopy,
  });

  final List<SftpEntry> rows;
  final int hiddenCount;
  final String? emptyCopy;

  factory SftpListView.build(List<SftpEntry> inventory, {required bool showHidden}) {
    final usable = inventory
        .where((e) => e.name != '.' && e.name != '..')
        .toList();
    final hiddenCount = usable.where((e) => e.isHidden).length;
    final rows = [
      for (final e in usable)
        if (showHidden || !e.isHidden) e,
    ]..sort(_byDirThenName);
    return SftpListView(
      rows: rows,
      hiddenCount: hiddenCount,
      emptyCopy: rows.isEmpty
          ? (usable.isEmpty
              ? 'This directory is empty.'
              : 'No visible files. Toggle hidden.')
          : null,
    );
  }
}

int _byDirThenName(SftpEntry a, SftpEntry b) {
  if (a.isDirectory != b.isDirectory) {
    return a.isDirectory ? -1 : 1;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
