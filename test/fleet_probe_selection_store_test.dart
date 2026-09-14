import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/fleet/fleet_probe_selection_store.dart';
import 'package:kelola/presentation/fleet/fleet_probe_policy.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kelola-fleet-sel-');
  });

  tearDown(() async {
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });

  File file() => File('${dir.path}/fleet_probe_selection.json');

  test('selection survives a new store on the same file', () async {
    final first = FleetProbeSelectionStore(file());
    await first.write({'h1', 'h2'});

    final restarted = FleetProbeSelectionStore(file());
    final read = await restarted.read({'h1', 'h2', 'h3'});

    expect(read, {'h1', 'h2'});
  });

  test('missing file is never chosen; a written empty list is an explicit zero', () async {
    final missing = FleetProbeSelectionStore(file());
    expect(await missing.read({'h1'}), isNull);

    await missing.write({});
    final again = FleetProbeSelectionStore(file());
    expect(await again.read({'h1'}), isEmpty);
  });

  test('read drops host ids that no longer exist and rewrites the file', () async {
    final store = FleetProbeSelectionStore(file());
    await store.write({'keep', 'deleted'});

    final read = await store.read({'keep'});
    expect(read, {'keep'});

    final again = FleetProbeSelectionStore(file());
    expect(await again.read({'keep', 'deleted'}), {'keep'});
  });

  test('a deleted host id does not keep occupying a free-fleet slot', () async {
    final store = FleetProbeSelectionStore(file());
    await store.write({'h1', 'h2', 'gone'});

    final kept = await store.read({'h1', 'h2', 'h3', 'h4', 'h5'});
    expect(kept, {'h1', 'h2'});

    final plan = planFleetProbes(
      hostIds: const ['h1', 'h2', 'h3', 'h4', 'h5'],
      selectedHostIds: kept,
      fleetUnlimited: false,
    );
    expect(plan.probedHostIds, {'h1', 'h2'});
    expect(plan.selectingAnotherIsLocked('h3'), isFalse);
    expect(plan.showChoosePrompt, isFalse);
  });
}
