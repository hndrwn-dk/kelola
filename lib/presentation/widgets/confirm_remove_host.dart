import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';

Future<bool> confirmRemoveHost(BuildContext context, String alias) {
  return showMutateConfirm(
    context,
    title: 'Remove $alias?',
    body:
        'This only deletes the host from this phone. The server and authorized_keys are unchanged, and the hardware key stays. The pinned host key and last-known health on this phone are discarded.',
    confirmLabel: 'Remove',
  );
}
