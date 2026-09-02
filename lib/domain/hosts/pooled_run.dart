import 'dart:async';

Future<void> runPooled<T>(
  Iterable<T> items, {
  int concurrency = 5,
  Duration timeout = const Duration(seconds: 10),
  required Future<void> Function(T item) fn,
  FutureOr<void> Function(T item, Object? error)? onItemDone,
}) async {
  final queue = List<T>.of(items);
  if (queue.isEmpty) {
    return;
  }
  final workers = concurrency.clamp(1, queue.length);
  Future<void> worker() async {
    while (true) {
      if (queue.isEmpty) {
        return;
      }
      final item = queue.removeAt(0);
      Object? error;
      try {
        await fn(item).timeout(timeout);
      } catch (e) {
        error = e;
      }
      if (onItemDone != null) {
        await onItemDone(item, error);
      }
    }
  }

  await Future.wait(List<Future<void>>.generate(workers, (_) => worker()));
}
