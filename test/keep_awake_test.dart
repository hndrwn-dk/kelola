import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/keep_awake/keep_awake.dart';

class _FakePort implements WakelockPort {
  final enabled = <bool>[];
  var throwNext = false;

  @override
  Future<void> setEnabled(bool value) async {
    if (throwNext) {
      throwNext = false;
      throw Exception('plugin');
    }
    enabled.add(value);
  }
}

void main() {
  test('ref-count enables on first hold and disables after last release',
      () async {
    final port = _FakePort();
    final lock = KeepAwake(port);
    await lock.acquire('follow');
    await lock.acquire('follow');
    await lock.acquire('transfer');
    expect(port.enabled, [true]);
    await lock.release('follow');
    expect(port.enabled, [true]);
    await lock.release('missing');
    await lock.release('transfer');
    expect(port.enabled, [true, false]);
  });

  test('plugin errors are swallowed', () async {
    final port = _FakePort()..throwNext = true;
    final lock = KeepAwake(port);
    await lock.acquire('command');
    expect(port.enabled, isEmpty);
    await lock.acquire('command');
    expect(port.enabled, isEmpty);
  });
}
