import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

enum SnippetListAction { edit, remove }

Future<SnippetListAction?> showSnippetListActions(
  BuildContext context, {
  required String name,
}) {
  final c = context.kc;
  return showModalBottomSheet<SnippetListAction>(
    context: context,
    backgroundColor: c.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) {
      return KelolaSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ServiceRow(
                risk: RiskLevel.mutate,
                name: 'Edit snippet',
                meta: name,
                onTap: () => Navigator.of(ctx).pop(SnippetListAction.edit),
              ),
              const SizedBox(height: 6),
              ServiceRow(
                risk: RiskLevel.destructive,
                name: 'Remove',
                meta: name,
                onTap: () => Navigator.of(ctx).pop(SnippetListAction.remove),
              ),
            ],
          ),
        ),
      );
    },
  );
}
