import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';

void main() {
  test('clear makes password unreachable', () {
    final p = EphemeralPassword();
    p.set('secret');
    expect(p.read(), 'secret');
    p.clear();
    expect(p.read(), isNull);
    expect(p.isSet, isFalse);
  });
}
