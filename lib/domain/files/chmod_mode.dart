int parseOctalMode(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t.length > 4) {
    throw FormatException('invalid mode');
  }
  final value = int.tryParse(t, radix: 8);
  if (value == null || value < 0 || value > 4095) {
    throw FormatException('invalid mode');
  }
  for (final ch in t.split('')) {
    if (ch.compareTo('0') < 0 || ch.compareTo('7') > 0) {
      throw FormatException('invalid mode');
    }
  }
  return value;
}

String formatPermissionBits(int mode) {
  final bits = mode & 0x1FF;
  const chars = 'rwxrwxrwx';
  final buf = StringBuffer();
  for (var i = 0; i < 9; i++) {
    final on = (bits & (1 << (8 - i))) != 0;
    buf.write(on ? chars[i] : '-');
  }
  return buf.toString();
}

String formatOctalMode(int mode) {
  return (mode & 0x1FF).toRadixString(8).padLeft(3, '0');
}
