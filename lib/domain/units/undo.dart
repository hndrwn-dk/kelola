import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/lockout.dart';
import 'package:kelola/domain/units/service_unit.dart';

const undoSnackDuration = Duration(seconds: 8);

/// Inverse of a reversible unit mutate. Null for destructive or one-way verbs.
///
/// Disable → enable. Stop of a non-lockout unit → start. Never invents undo
/// for something already destroyed (remove, reboot) or for lockout stop/disable.
UnitActionProbe? undoProbeFor(UnitActionProbe action) {
  if (action.risk == RiskLevel.destructive) {
    return null;
  }
  if (isDestructiveUnitAction(action.verb, action.unitName)) {
    return null;
  }
  switch (action.verb) {
    case UnitVerb.disable:
      return UnitActionProbe(unitName: action.unitName, verb: UnitVerb.enable);
    case UnitVerb.stop:
      return UnitActionProbe(unitName: action.unitName, verb: UnitVerb.start);
    case UnitVerb.start:
    case UnitVerb.restart:
    case UnitVerb.reload:
    case UnitVerb.enable:
      return null;
  }
}
