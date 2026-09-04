import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/hosts/pooled_run.dart';

void main() {
  test('slow host timeout does not block others; callbacks progressive', () async {
    final done = <int>[];
    final started = DateTime.now();
    await runPooled(
      [1, 2, 3],
      concurrency: 2,
      timeout: const Duration(milliseconds: 80),
      fn: (id) async {
        if (id == 2) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      },
      onItemDone: (id, error) {
        done.add(id);
      },
    );
    final elapsed = DateTime.now().difference(started);
    expect(done.toSet(), {1, 2, 3});
    expect(elapsed.inMilliseconds, lessThan(350));
    expect(done.indexOf(1) < done.indexOf(2) || done.indexOf(3) < done.indexOf(2), isTrue);
  });
}
