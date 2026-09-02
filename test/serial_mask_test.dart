import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/serial_mask.dart';

void main() {
  test('masks serial keeping last four characters', () {
    expect(maskSerial('ABC1237F2K'), '···· 7F2K');
  });

  test('empty serial is omitted', () {
    expect(maskSerial(''), isNull);
    expect(maskSerial('   '), isNull);
    expect(maskSerial(null), isNull);
  });

  test('serial shorter than four keeps every character after the mask', () {
    expect(maskSerial('F2K'), '···· F2K');
    expect(maskSerial('K'), '···· K');
  });
}
