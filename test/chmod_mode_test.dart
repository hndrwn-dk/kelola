import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/files/chmod_mode.dart';

void main() {
  test('octal round-trips to rwx and rejects junk', () {
    expect(formatPermissionBits(420), 'rw-r--r--');
    expect(parseOctalMode('644'), 420);
    expect(parseOctalMode('0644'), 420);
    expect(parseOctalMode('755'), 493);
    expect(() => parseOctalMode('999'), throwsFormatException);
    expect(() => parseOctalMode(''), throwsFormatException);
  });
}
