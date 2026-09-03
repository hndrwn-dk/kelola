import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/domain/units/undo.dart';

void main() {
  test('disable undoes with enable on the same unit', () {
    const action = UnitActionProbe(
      unitName: 'nginx.service',
      verb: UnitVerb.disable,
    );
    final undo = undoProbeFor(action);
    expect(undo, isNotNull);
    expect(undo!.unitName, 'nginx.service');
    expect(undo.verb, UnitVerb.enable);
    expect(undo.runtimeType, UnitActionProbe);
  });

  test('stop of a non-lockout unit undoes with start', () {
    const action = UnitActionProbe(
      unitName: 'nginx.service',
      verb: UnitVerb.stop,
    );
    final undo = undoProbeFor(action);
    expect(undo, isNotNull);
    expect(undo!.verb, UnitVerb.start);
    expect(undo.unitName, 'nginx.service');
  });

  test('destructive lockout stop and disable have no undo', () {
    expect(
      undoProbeFor(
        const UnitActionProbe(unitName: 'sshd.service', verb: UnitVerb.stop),
      ),
      isNull,
    );
    expect(
      undoProbeFor(
        const UnitActionProbe(unitName: 'sshd.service', verb: UnitVerb.disable),
      ),
      isNull,
    );
  });

  test('restart, reload, start, enable have no undo', () {
    for (final verb in [
      UnitVerb.restart,
      UnitVerb.reload,
      UnitVerb.start,
      UnitVerb.enable,
    ]) {
      expect(
        undoProbeFor(UnitActionProbe(unitName: 'nginx.service', verb: verb)),
        isNull,
        reason: '$verb must not promise undo',
      );
    }
  });

  test('undo window is 8 seconds', () {
    expect(undoSnackDuration, const Duration(seconds: 8));
  });

  test('undo of disable is a Probe through execute and writes a second audit',
      () async {
    final titles = <String>[];
    Future<void> execute(UnitActionProbe probe) async {
      titles.add(probe.auditTitle);
    }

    const disable = UnitActionProbe(
      unitName: 'nginx.service',
      verb: UnitVerb.disable,
    );
    await execute(disable);
    final undo = undoProbeFor(disable);
    expect(undo, isNotNull);
    await execute(undo!);

    expect(titles, [
      'Disabled nginx.service',
      'Enabled nginx.service',
    ]);
  });

  test('undo helper source is a Probe, not a raw SSH call', () {
    final src = File('lib/domain/units/undo.dart').readAsStringSync();
    expect(src, contains('UnitActionProbe'));
    expect(src, isNot(contains('dartssh2')));
    expect(src, isNot(contains('SSHClient')));
    expect(src, isNot(contains('.run(')));
  });
}
