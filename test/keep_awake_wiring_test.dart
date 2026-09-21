import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('call sites acquire and release keep-awake tokens', () {
    final journal =
        File('lib/presentation/screens/journal_screen.dart').readAsStringSync();
    expect(journal, contains("acquire('follow')"));
    expect(journal, contains("release('follow')"));

    final files =
        File('lib/presentation/screens/files_screen.dart').readAsStringSync();
    expect(files, contains("acquire('transfer')"));
    expect(files, contains("release('transfer')"));

    final command =
        File('lib/presentation/screens/terminal_sheet.dart').readAsStringSync();
    expect(command, contains("acquire('command')"));
    expect(command, contains("release('command')"));

    final tunnels =
        File('lib/presentation/tunnels_keep_awake.dart').readAsStringSync();
    expect(tunnels, contains("acquire('tunnels')"));
    expect(tunnels, contains("release('tunnels')"));
  });
}
