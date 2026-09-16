import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/snippet_probe.dart';
import 'package:kelola/domain/snippets/run_snippet.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart'
    show KelolaEmpty;
import 'package:kelola/presentation/widgets/snippet_list_actions.dart';
import 'package:kelola/providers.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

class SnippetsScreen extends ConsumerStatefulWidget {
  const SnippetsScreen({super.key, required this.host, this.onExecute});

  final Host host;

  /// Test seam. When set, Run hands this the same probe the preview shows
  /// and does not open an SSH session. A returned result is the transcript.
  final Future<CommandRunnerResult?> Function(SnippetProbe probe)? onExecute;

  @override
  ConsumerState<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends ConsumerState<SnippetsScreen> {
  List<Snippet> _items = const [];
  String? _error;
  String? _notice;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await ref.read(hostRepositoryProvider).listSnippets();
      setState(() => _items = items);
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Scaffold(
      backgroundColor: c.ink,
      appBar: KelolaHostAppBar(
        hostAlias: widget.host.alias,
        title: 'Snippets',
      ),
      body: Column(
        children: [
          if (_busy)
            LinearProgressIndicator(
              minHeight: 1.5,
              backgroundColor: c.surface,
              color: c.amber,
            ),
          Expanded(
            child: ListView(
              padding: kelolaScrollPadding(context),
              children: [
                if (_error != null) ...[
                  KelolaError(message: _error!, sudoUser: widget.host.username),
                  const SizedBox(height: 12),
                ],
                if (_notice != null) ...[
                  Text(
                    _notice!,
                    style: KelolaType.body(color: c.muted, size: 13),
                  ),
                  const SizedBox(height: 12),
                ],
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'New snippet',
                  meta: 'template · {{unit}} {{path}} {{port}} {{host}}',
                  onTap: _busy ? null : _create,
                ),
                const SizedBox(height: 6),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Export JSON',
                  meta: '${_items.length} templates',
                  onTap: _items.isEmpty ? null : _export,
                ),
                const SizedBox(height: 6),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Import JSON',
                  meta: 'merge into library',
                  onTap: _busy ? null : _import,
                ),
                const SizedBox(height: 6),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Restore starter snippets',
                  meta: 'put back missing starters',
                  onTap: _busy ? null : _restore,
                ),
                const SizedBox(height: 12),
                const SectionSlab('Library'),
                const SizedBox(height: 6),
                if (_items.isEmpty && !_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: KelolaEmpty(
                      body: 'Add a snippet. It will be risk-classified and never auto-run.',
                    ),
                  ),
                for (final snippet in _items) ...[
                  _snippetRow(c, snippet),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  RiskLevel _previewRisk(Snippet snippet) {
    try {
      return snippetToProbe(
        snippet,
        SnippetBindings(host: widget.host.alias),
      ).risk;
    } on SnippetUnboundException {
      final filled = SnippetBindings(
        unit: 'nginx.service',
        path: '/',
        port: '22',
        host: widget.host.alias,
      );
      return snippetToProbe(snippet, filled).risk;
    }
  }

  Future<void> _openRun(Snippet snippet) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.kc.ink,
      builder: (ctx) => KelolaSheet(
        child: SizedBox(
          height: kelolaSheetBodyHeight(ctx),
          child: _SnippetRunSheet(
            host: widget.host,
            snippet: snippet,
            onExecute: widget.onExecute,
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final created = await _editSnippet(
      context,
      const Snippet(id: '', name: '', template: ''),
    );
    if (created == null) {
      return;
    }
    final saved = Snippet(
      id: const Uuid().v7(),
      name: created.name,
      template: created.template,
    );
    await ref.read(hostRepositoryProvider).upsertSnippet(saved);
    await _load();
  }

  Future<void> _export() {
    return Share.share(encodeSnippets(_items), subject: 'Kelola snippets');
  }

  Widget _snippetRow(KelolaColors c, Snippet snippet) {
    return Dismissible(
      key: ValueKey(snippet.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          color: c.amber.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(KelolaRadii.md),
        ),
        child: Text(
          'EDIT',
          style: KelolaType.mono(
            color: c.amber,
            size: 11,
            weight: FontWeight.w500,
          ),
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: c.red.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(KelolaRadii.md),
        ),
        child: Text(
          'REMOVE',
          style: KelolaType.mono(
            color: c.red,
            size: 11,
            weight: FontWeight.w500,
          ),
        ),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await _edit(snippet);
        } else {
          await _remove(snippet);
        }
        return false;
      },
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.25,
        DismissDirection.endToStart: 0.25,
      },
      child: ServiceRow(
        risk: _previewRisk(snippet),
        name: snippet.name,
        meta: snippet.starter ? 'starter · tap to run' : 'tap to run',
        onTap: _busy ? null : () => _openRun(snippet),
        onLongPress: _busy ? null : () => _actions(snippet),
      ),
    );
  }

  Future<void> _actions(Snippet snippet) async {
    final action = await showSnippetListActions(context, name: snippet.name);
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case SnippetListAction.edit:
        await _edit(snippet);
      case SnippetListAction.remove:
        await _remove(snippet);
    }
  }

  Future<void> _edit(Snippet snippet) async {
    final edited = await _editSnippet(context, snippet);
    if (edited == null || !mounted) {
      return;
    }
    await ref
        .read(hostRepositoryProvider)
        .upsertSnippet(
          Snippet(
            id: snippet.id,
            name: edited.name,
            template: edited.template,
            starter: false,
          ),
        );
    await _load();
  }

  Future<void> _remove(Snippet snippet) async {
    final ok = await showMutateConfirm(
      context,
      title: 'Remove ${snippet.name}?',
      body: 'This cannot be undone.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) {
      return;
    }
    await ref.read(hostRepositoryProvider).deleteSnippet(snippet.id);
    await _load();
  }

  Future<void> _restore() async {
    final added =
        await ref.read(hostRepositoryProvider).restoreStarterSnippets();
    await _load();
    if (!mounted) {
      return;
    }
    setState(() {
      _notice = added == 0
          ? 'Starter snippets are already in the library.'
          : (added == 1
              ? 'Restored 1 starter snippet.'
              : 'Restored $added starter snippets.');
    });
  }

  Future<void> _import() async {
    final raw = await _promptJson(context);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    final decoded = decodeSnippets(raw);
    final repo = ref.read(hostRepositoryProvider);
    for (final snippet in decoded) {
      if (snippet.id.isEmpty || snippet.template.isEmpty) {
        continue;
      }
      await repo.upsertSnippet(snippet);
    }
    await _load();
  }
}

class _SnippetRunSheet extends ConsumerStatefulWidget {
  const _SnippetRunSheet({
    required this.host,
    required this.snippet,
    this.onExecute,
  });

  final Host host;
  final Snippet snippet;
  final Future<CommandRunnerResult?> Function(SnippetProbe probe)? onExecute;

  @override
  ConsumerState<_SnippetRunSheet> createState() => _SnippetRunSheetState();
}

class _SnippetRunSheetState extends ConsumerState<_SnippetRunSheet> {
  late final TextEditingController _unit;
  late final TextEditingController _path;
  late final TextEditingController _port;
  late final TextEditingController _hostAlias;
  String? _error;
  String? _out;
  bool _busy = false;

  Set<String> get _needed => snippetPlaceholders(widget.snippet.template);

  @override
  void initState() {
    super.initState();
    _unit = TextEditingController();
    _path = TextEditingController(text: '/');
    _port = TextEditingController();
    _hostAlias = TextEditingController(text: widget.host.alias);
  }

  @override
  void dispose() {
    _unit.dispose();
    _path.dispose();
    _port.dispose();
    _hostAlias.dispose();
    super.dispose();
  }

  SnippetBindings get _bindings => SnippetBindings(
    unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
    path: _path.text.trim().isEmpty ? null : _path.text.trim(),
    port: _port.text.trim().isEmpty ? null : _port.text.trim(),
    host: _hostAlias.text.trim().isEmpty ? null : _hostAlias.text.trim(),
  );

  SnippetRender get _render =>
      renderSnippet(widget.snippet.template, _bindings);

  /// Preview and execution both use this probe. Null means do not run.
  SnippetProbe? get _probe {
    try {
      return snippetToProbe(widget.snippet, _bindings);
    } on SnippetUnboundException {
      return null;
    }
  }

  String? _fieldError(String name) {
    if (_render.emptyPlaceholders.contains(name)) {
      return 'Required';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final probe = _probe;
    return Scaffold(
      backgroundColor: c.ink,
      appBar: KelolaHostAppBar(
        hostAlias: widget.host.alias,
        title: widget.snippet.name,
      ),
      body: ListView(
        padding: kelolaScrollPadding(context),
        children: [
          if (_needed.contains('unit')) ...[
            KelolaInput(
              label: 'unit',
              controller: _unit,
              mono: true,
              hint: 'nginx.service',
              error: _fieldError('unit'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
          ],
          if (_needed.contains('path')) ...[
            KelolaInput(
              label: 'path',
              controller: _path,
              mono: true,
              hint: '/',
              error: _fieldError('path'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
          ],
          if (_needed.contains('port')) ...[
            KelolaInput(
              label: 'port',
              controller: _port,
              mono: true,
              hint: '443',
              keyboardType: TextInputType.number,
              error: _fieldError('port'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
          ],
          if (_needed.contains('host')) ...[
            KelolaInput(
              label: 'host',
              controller: _hostAlias,
              mono: true,
              error: _fieldError('host'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            'PREVIEW',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 6),
          RiskBand(
            risk: probe?.risk ?? RiskLevel.read,
            child: SelectableText(
              probe?.commandLine ?? widget.snippet.template,
              style: KelolaType.mono(color: c.text, size: 11),
            ),
          ),
          const SizedBox(height: 10),
          ServiceRow(
            risk: probe?.risk ?? RiskLevel.read,
            name: 'Run',
            meta: probe == null
                ? 'fill placeholders'
                : '${probe.risk.name} · execute only',
            onTap: _busy || probe == null ? null : () => _run(probe),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            KelolaError(message: _error!, sudoUser: widget.host.username),
          ],
          if (_busy && _out == null) ...[
            const SizedBox(height: 12),
            Text('Running', style: KelolaType.mono(color: c.muted, size: 10.5)),
          ],
          if (_out != null) ...[
            const SizedBox(height: 12),
            RiskBand(
              risk: RiskLevel.read,
              child: SelectableText(
                _out!,
                style: KelolaType.mono(color: c.muted, size: 10.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _run(SnippetProbe probe) async {
    if (probe.risk != RiskLevel.read) {
      final allowed = await _confirm(context, probe);
      if (!allowed || !mounted) {
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _out = null;
    });
    try {
      final execute = widget.onExecute;
      if (execute != null) {
        final result = await execute(probe);
        if (!mounted || result == null) {
          return;
        }
        setState(() => _out = formatCommandRun(probe.commandLine, result));
        return;
      }
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final result = await runSnippet<CommandRunnerResult>(
        host: widget.host,
        probe: probe,
        execute: <T>(host, p) =>
            runHostProbe<T>(ref: ref, context: context, host: host, probe: p),
        scope: ProbeScope.host,
      );
      if (!mounted) {
        return;
      }
      setState(() => _out = formatCommandRun(probe.commandLine, result));
    } on ReadOnlyViolation {
      setState(() => _error = 'This host is read-only.');
    } on SnippetFleetForbidden {
      setState(() => _error = 'Snippets cannot run in fleet mode.');
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirm(BuildContext context, SnippetProbe probe) {
    switch (probe.risk) {
      case RiskLevel.read:
        return Future.value(true);
      case RiskLevel.mutate:
        return showMutateConfirm(
          context,
          title: 'Run ${probe.name}?',
          body: 'This changes state on ${widget.host.alias}.',
          confirmLabel: 'Run',
        );
      case RiskLevel.destructive:
        return _confirmDestructive(context, probe);
    }
  }

  Future<bool> _confirmDestructive(
    BuildContext context,
    SnippetProbe probe,
  ) async {
    var confirmed = false;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return KelolaSheet(
          child: DestructiveConfirmSheet(
            title: 'Run ${probe.name}?',
            consequence:
                'This will end your session and may make ${widget.host.alias} unreachable.',
            warning: 'You will lose access immediately. Recovery needs physical or console access to the machine.',
            confirmToken: widget.host.alias,
            onConfirmed: () => confirmed = true,
          ),
        );
      },
    );
    return confirmed;
  }
}

class _SnippetDraft {
  const _SnippetDraft({required this.name, required this.template});

  final String name;
  final String template;
}

Future<Snippet?> _editSnippet(BuildContext context, Snippet current) async {
  final draft = await showModalBottomSheet<_SnippetDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.kc.ink,
    builder: (ctx) => KelolaSheet(child: _SnippetEditor(current: current)),
  );
  if (draft == null) {
    return null;
  }
  if (draft.name.isEmpty || draft.template.isEmpty) {
    return null;
  }
  return Snippet(
    id: current.id,
    name: draft.name,
    template: draft.template,
    starter: current.starter,
  );
}

class _SnippetEditor extends StatefulWidget {
  const _SnippetEditor({required this.current});

  final Snippet current;

  @override
  State<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<_SnippetEditor> {
  late final TextEditingController _name;
  late final TextEditingController _template;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.current.name);
    _template = TextEditingController(text: widget.current.template);
  }

  @override
  void dispose() {
    _name.dispose();
    _template.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      _SnippetDraft(name: _name.text.trim(), template: _template.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KelolaInput(label: 'Name', controller: _name),
          const SizedBox(height: 10),
          KelolaInput(
            label: 'Template',
            controller: _template,
            mono: true,
            hint: 'systemctl status {{unit}}',
          ),
          const SizedBox(height: 12),
          ServiceRow(
            risk: RiskLevel.read,
            name: 'Save',
            meta: 'library only · not run',
            onTap: _save,
          ),
        ],
      ),
    );
  }
}

Future<String?> _promptJson(BuildContext context) async {
  final raw = TextEditingController();
  final c = context.kc;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.ink,
    builder: (ctx) {
      return KelolaSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KelolaInput(label: 'JSON', controller: raw, mono: true),
              const SizedBox(height: 12),
              ServiceRow(
                risk: RiskLevel.read,
                name: 'Import',
                meta: 'does not run snippets',
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ),
      );
    },
  );
  final text = ok == true ? raw.text : null;
  raw.dispose();
  return text;
}
