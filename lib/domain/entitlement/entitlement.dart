import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola_pro/kelola_pro.dart';

export 'package:kelola_pro/kelola_pro.dart';

final entitlementProvider = Provider<Entitlement>((ref) {
  final entitlement = createEntitlement();
  entitlement.initialize();
  ref.onDispose(entitlement.dispose);
  return entitlement;
});

/// Rebuilds listeners when [Entitlement.changes] emits. Yields 0 immediately
/// so the first frame does not wait on the stream.
final entitlementRevisionProvider = StreamProvider<int>((ref) async* {
  final entitlement = ref.watch(entitlementProvider);
  yield 0;
  var revision = 0;
  await for (final _ in entitlement.changes) {
    yield ++revision;
  }
});
