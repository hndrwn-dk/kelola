import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

/// Shared API-key control for Assist providers.
///
/// When [storedHint] is set, the full key is never loaded into a controller.
/// Replace commits via [onReplace]; first-time entry reports via [onDraftChanged].
class LlmApiKeyField extends StatefulWidget {
  const LlmApiKeyField({
    super.key,
    required this.storedHint,
    this.onReplace,
    this.onRemove,
    this.onDraftChanged,
  });

  /// Masked hint from the repository, or null when no key is stored.
  final String? storedHint;
  final Future<void> Function(String trimmedKey)? onReplace;
  final Future<void> Function()? onRemove;
  final ValueChanged<String?>? onDraftChanged;

  @override
  State<LlmApiKeyField> createState() => LlmApiKeyFieldState();
}

@visibleForTesting
class LlmApiKeyFieldState extends State<LlmApiKeyField>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  bool _obscured = true;
  bool _replacing = false;
  bool _busy = false;

  bool get _hasStored =>
      widget.storedHint != null && widget.storedHint!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_emitDraft);
  }

  @override
  void didUpdateWidget(covariant LlmApiKeyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storedHint != widget.storedHint && _hasStored) {
      _replacing = false;
      _controller.clear();
      _obscured = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_emitDraft)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) &&
        !_obscured) {
      setState(() => _obscured = true);
    }
  }

  void _emitDraft() {
    if (_hasStored && !_replacing) {
      return;
    }
    final trimmed = _controller.text.trim();
    widget.onDraftChanged?.call(trimmed.isEmpty ? null : trimmed);
  }

  Future<void> _commitReplace() async {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty || _busy) {
      return;
    }
    final onReplace = widget.onReplace;
    if (onReplace == null) {
      return;
    }
    setState(() => _busy = true);
    await onReplace(trimmed);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _replacing = false;
      _controller.clear();
      _obscured = true;
    });
  }

  Future<void> _remove() async {
    final onRemove = widget.onRemove;
    if (onRemove == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    await onRemove();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _replacing = false;
      _controller.clear();
      _obscured = true;
    });
  }

  Widget _secretField({required bool showActions}) {
    final c = context.kc;
    final trimmed = _controller.text.trim();
    final canSave = trimmed.isNotEmpty && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('API key', style: KelolaType.body(color: c.muted, size: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _controller,
          obscureText: _obscured,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          autofillHints: const <String>[],
          keyboardType: TextInputType.visiblePassword,
          style: KelolaType.mono(color: c.text, size: 13),
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'[\u0000-\u0008]')),
          ],
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: c.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            suffixIcon: IconButton(
              tooltip: _obscured ? 'Show API key' : 'Hide API key',
              onPressed: () => setState(() => _obscured = !_obscured),
              icon: Icon(
                _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: c.muted,
                size: 20,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KelolaRadii.sm),
              borderSide: BorderSide(color: c.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KelolaRadii.sm),
              borderSide: BorderSide(color: c.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KelolaRadii.sm),
              borderSide: BorderSide(color: c.amber),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (showActions) ...[
          const SizedBox(height: 8),
          ServiceRow(
            risk: RiskLevel.mutate,
            name: 'Save',
            meta: canSave ? 'store on this device' : 'enter a key',
            onTap: canSave ? _commitReplace : null,
          ),
          const SizedBox(height: 8),
          ServiceRow(
            risk: RiskLevel.read,
            name: 'Cancel',
            meta: 'keep current key',
            onTap: _busy
                ? null
                : () {
                    setState(() {
                      _replacing = false;
                      _controller.clear();
                      _obscured = true;
                    });
                  },
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    if (_hasStored && !_replacing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('API key', style: KelolaType.body(color: c.muted, size: 12)),
          const SizedBox(height: 6),
          ServiceRow(
            risk: RiskLevel.read,
            name: 'Saved key',
            meta: widget.storedHint!,
          ),
          const SizedBox(height: 8),
          ServiceRow(
            risk: RiskLevel.mutate,
            name: 'Replace key',
            meta: 'enter a new value',
            onTap: _busy
                ? null
                : () {
                    setState(() {
                      _replacing = true;
                      _controller.clear();
                      _obscured = true;
                    });
                  },
          ),
          const SizedBox(height: 8),
          ServiceRow(
            risk: RiskLevel.destructive,
            name: 'Remove key',
            meta: 'delete from this device',
            onTap: _busy ? null : _remove,
          ),
        ],
      );
    }
    return _secretField(showActions: _replacing);
  }
}
