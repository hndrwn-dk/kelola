import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/hosts/pooled_run.dart';

void main() {
  test('runPooled keeps at most five hosts in flight', () async {
    var inFlight = 0;
    var maxInFlight = 0;
    await runPooled(
      List<int>.generate(12, (i) => i),
      concurrency: 5,
      timeout: const Duration(seconds: 10),
      fn: (i) async {
        inFlight++;
        if (inFlight > maxInFlight) {
          maxInFlight = inFlight;
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
        inFlight--;
      },
    );
    expect(maxInFlight, 5);
  });

  test('runPooled times out a hung host and keeps going', () async {
    final finished = <String>[];
    final errors = <String, Object?>{};
    await runPooled(
      const ['fast', 'slow', 'also-fast'],
      concurrency: 2,
      timeout: const Duration(milliseconds: 80),
      fn: (id) async {
        if (id == 'slow') {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      },
      onItemDone: (id, error) {
        finished.add(id);
        errors[id] = error;
      },
    );
    expect(finished.toSet(), {'fast', 'slow', 'also-fast'});
    expect(errors['fast'], isNull);
    expect(errors['also-fast'], isNull);
    expect(errors['slow'], isA<TimeoutException>());
  });

  test('runPooled reports item errors without aborting the rest', () async {
    final errors = <int, Object?>{};
    await runPooled(
      const [1, 2, 3],
      concurrency: 2,
      timeout: const Duration(seconds: 2),
      fn: (i) async {
        if (i == 2) {
          throw StateError('down');
        }
      },
      onItemDone: (i, error) => errors[i] = error,
    );
    expect(errors[1], isNull);
    expect(errors[2], isA<StateError>());
    expect(errors[3], isNull);
  });
}
