import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/host_env/host_env.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/providers.dart';
import 'package:uuid/uuid.dart';

Future<void> showTagEnvironmentsSheet({
  required BuildContext context,
}) {
  final c = context.kc;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) {
      return KelolaSheet(
        child: SizedBox(
          height: kelolaSheetBodyHeight(ctx),
          child: const _TagEnvSheet(),
        ),
      );
    },
  );
}

class HostEnvSection extends StatelessWidget {
  const HostEnvSection({super.key, required this.host});

  final Host host;

  @override
  Widget build(BuildContext context) {
    return ServiceRow(
      risk: RiskLevel.read,
      name: 'Environment',
      meta: 'overrides and inherited',
      onTap: () => showHostEnvironmentsSheet(context: context, host: host),
    );
  }
}

Future<void> showHostEnvironmentsSheet({
  required BuildContext context,
  required Host host,
}) {
  final c = context.kc;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) {
      return KelolaSheet(
        child: SizedBox(
          height: kelolaSheetBodyHeight(ctx),
          child: _HostEnvSheet(host: host),
        ),
      );
    },
  );
}

class _HostEnvSheet extends ConsumerStatefulWidget {
  const _HostEnvSheet({required this.host});

  final Host host;

  @override
  ConsumerState<_HostEnvSheet> createState() => _HostEnvSheetState();
}

class _HostEnvSheetState extends ConsumerState<_HostEnvSheet> {
  List<EnvBinding> _all = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await ref.read(hostRepositoryProvider).listEnvBindings();
    if (!mounted) {
      return;
    }
    setState(() => _all = rows);
  }

  Future<void> _edit({EnvBinding? existing}) async {
    final saved = await _showEnvEditor(
      context: context,
      scope: EnvScope.host,
      scopeId: widget.host.id,
      existing: existing,
      tags: const [],
    );
    if (saved) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final host = widget.host;
    final inherited = [
      for (final binding in _all)
        if (binding.scope == EnvScope.tag && host.tags.contains(binding.scopeId))
          binding,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final overrides = [
      for (final binding in _all)
        if (binding.scope == EnvScope.host && binding.scopeId == host.id)
          binding,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return ListView(
      padding: kelolaScrollPadding(context, top: 16),
      children: [
        Text('Environment', style: KelolaType.display(color: c.text, size: 16)),
        const SizedBox(height: 8),
        Text(
          'Inherited tag variables apply first. Host overrides win.',
          style: KelolaType.body(color: c.muted, size: 13),
        ),
        const SizedBox(height: 14),
        if (inherited.isEmpty && overrides.isEmpty)
          const ServiceRow(
            risk: RiskLevel.read,
            name: 'No variables',
            meta: 'commands and snippets only',
          ),
        for (var i = 0; i < inherited.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          ServiceRow(
            risk: RiskLevel.read,
            kicker: 'from ${inherited[i].scopeId}',
            name: inherited[i].name,
            meta: inherited[i].value,
          ),
        ],
        if (inherited.isNotEmpty && overrides.isNotEmpty)
          const SizedBox(height: 8),
        for (var i = 0; i < overrides.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          ServiceRow(
            risk: RiskLevel.read,
            name: overrides[i].name,
            meta: overrides[i].value,
            onTap: () => _edit(existing: overrides[i]),
          ),
        ],
        const SizedBox(height: 8),
        ServiceRow(
          risk: RiskLevel.read,
          name: 'Add variable',
          meta: 'host override',
          onTap: () => _edit(),
        ),
      ],
    );
  }
}

class _TagEnvSheet extends ConsumerStatefulWidget {
  const _TagEnvSheet();

  @override
  ConsumerState<_TagEnvSheet> createState() => _TagEnvSheetState();
}

class _TagEnvSheetState extends ConsumerState<_TagEnvSheet> {
  List<EnvBinding> _rows = const [];
  List<String> _tags = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = ref.read(hostRepositoryProvider);
    final rows = await repo.listEnvBindings();
    final hosts = await repo.list();
    final tags = {
      for (final host in hosts) ...host.tags,
      for (final row in rows)
        if (row.scope == EnvScope.tag) row.scopeId,
    }.where((tag) => tag.isNotEmpty).toList()
      ..sort();
    if (!mounted) {
      return;
    }
    setState(() {
      _rows = [
        for (final row in rows)
          if (row.scope == EnvScope.tag) row,
      ]..sort((a, b) {
          final byTag = a.scopeId.compareTo(b.scopeId);
          return byTag != 0 ? byTag : a.name.compareTo(b.name);
        });
      _tags = tags;
    });
  }

  Future<void> _edit({EnvBinding? existing}) async {
    final saved = await _showEnvEditor(
      context: context,
      scope: EnvScope.tag,
      scopeId: existing?.scopeId ?? (_tags.isEmpty ? '' : _tags.first),
      existing: existing,
      tags: _tags,
    );
    if (saved) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return ListView(
      padding: kelolaScrollPadding(context, top: 16),
      children: [
        Text('Environments', style: KelolaType.display(color: c.text, size: 16)),
        const SizedBox(height: 8),
        Text(
          'Tag variables apply to every host with that tag. Host overrides live on Edit host.',
          style: KelolaType.body(color: c.muted, size: 13),
        ),
        const SizedBox(height: 14),
        if (_rows.isEmpty)
          const ServiceRow(
            risk: RiskLevel.read,
            name: 'No tag variables',
            meta: 'commands and snippets only',
          ),
        for (var i = 0; i < _rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          ServiceRow(
            risk: RiskLevel.read,
            kicker: _rows[i].scopeId,
            name: _rows[i].name,
            meta: _rows[i].value,
            onTap: () => _edit(existing: _rows[i]),
          ),
        ],
        const SizedBox(height: 8),
        ServiceRow(
          risk: RiskLevel.read,
          name: 'Add variable',
          meta: 'tag scope',
          onTap: () => _edit(),
        ),
      ],
    );
  }
}

Future<bool> _showEnvEditor({
  required BuildContext context,
  required EnvScope scope,
  required String scopeId,
  required EnvBinding? existing,
  required List<String> tags,
}) async {
  final c = context.kc;
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) {
      return KelolaSheet(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            16,
            14,
            MediaQuery.viewInsetsOf(ctx).bottom + 12,
          ),
          child: _EnvEditorForm(
            scope: scope,
            scopeId: scopeId,
            existing: existing,
            tags: tags,
          ),
        ),
      );
    },
  );
  return result ?? false;
}

class _EnvEditorForm extends ConsumerStatefulWidget {
  const _EnvEditorForm({
    required this.scope,
    required this.scopeId,
    required this.existing,
    required this.tags,
  });

  final EnvScope scope;
  final String scopeId;
  final EnvBinding? existing;
  final List<String> tags;

  @override
  ConsumerState<_EnvEditorForm> createState() => _EnvEditorFormState();
}

class _EnvEditorFormState extends ConsumerState<_EnvEditorForm> {
  late final TextEditingController _name;
  late final TextEditingController _value;
  late final TextEditingController _tag;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _value = TextEditingController(text: widget.existing?.value ?? '');
    _tag = TextEditingController(
      text: widget.existing?.scopeId ?? widget.scopeId,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (!isEnvName(name)) {
      setState(() => _nameError = 'Use letters, digits, underscore');
      return;
    }
    final scopeId = widget.scope == EnvScope.tag
        ? _tag.text.trim()
        : widget.scopeId;
    if (scopeId.isEmpty) {
      setState(() => _nameError = 'Tag is required');
      return;
    }
    await ref.read(hostRepositoryProvider).upsertEnvBinding(
      EnvBinding(
        id: widget.existing?.id ?? const Uuid().v7(),
        scope: widget.scope,
        scopeId: scopeId,
        name: name,
        value: _value.text,
      ),
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _remove() async {
    final existing = widget.existing;
    if (existing == null) {
      return;
    }
    await ref.read(hostRepositoryProvider).deleteEnvBinding(existing.id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.existing == null ? 'Add variable' : 'Edit variable',
          style: KelolaType.display(color: c.text, size: 16),
        ),
        if (widget.scope == EnvScope.tag) ...[
          const SizedBox(height: 14),
          if (widget.tags.isNotEmpty) ...[
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final tag in widget.tags)
                  FilterPill(
                    label: tag,
                    selected: _tag.text.trim() == tag,
                    onTap: () => setState(() => _tag.text = tag),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          KelolaInput(
            label: 'Tag',
            controller: _tag,
            hint: 'prod',
          ),
        ],
        const SizedBox(height: 14),
        KelolaInput(
          label: 'Name',
          controller: _name,
          hint: 'REGION',
          error: _nameError,
        ),
        const SizedBox(height: 14),
        KelolaInput(
          label: 'Value',
          controller: _value,
          hint: 'us-east',
          mono: true,
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: c.amber),
          child: Text(
            'Save',
            style: KelolaType.display(color: c.ink, size: 13),
          ),
        ),
        if (widget.existing != null) ...[
          const SizedBox(height: 8),
          ServiceRow(
            risk: RiskLevel.destructive,
            name: 'Remove',
            meta: widget.existing!.name,
            onTap: _remove,
          ),
        ],
      ],
    );
  }
}
