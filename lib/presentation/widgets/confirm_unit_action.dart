import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/units/lockout.dart';
import 'package:kelola/domain/units/service_unit.dart';

Future<bool> confirmUnitAction(
  BuildContext context, {
  required String hostAlias,
  required String unit,
  required UnitVerb verb,
}) async {
  final title =
      '${verb.name[0].toUpperCase()}${verb.name.substring(1)} $unit?';
  if (isDestructiveUnitAction(verb, unit)) {
    var confirmed = false;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: DestructiveConfirmSheet(
            title: title,
            consequence:
                'This will end your session and may make $hostAlias unreachable.',
            warning:
                'You will lose access immediately. Recovery needs physical or console access to the machine.',
            confirmToken: hostAlias,
            onConfirmed: () => confirmed = true,
          ),
        );
      },
    );
    return confirmed;
  }

  return showMutateConfirm(
    context,
    title: title,
    body: 'This changes state on $hostAlias.',
    confirmLabel: verb.name,
  );
}
