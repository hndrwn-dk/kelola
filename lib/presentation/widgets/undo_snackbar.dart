import 'package:flutter/material.dart';
import 'package:kelola/domain/units/undo.dart';

void showUndoSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: undoSnackDuration,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: onUndo,
      ),
    ),
  );
}
