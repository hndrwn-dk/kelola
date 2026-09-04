import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';
import 'package:kelola/providers.dart';

class LlmSettingsScreen extends ConsumerStatefulWidget {
  const LlmSettingsScreen({super.key});

  @override
  ConsumerState<LlmSettingsScreen> createState() => _LlmSettingsScreenState();
}

class _LlmSettingsScreenState extends ConsumerState<LlmSettingsScreen> {
  LlmSettingsBundle _bundle = const LlmSettingsBundle();
  LlmProvider _draft = LlmProvider.none;
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  bool _busy = true;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bundle =
        await ref.read(hostRepositoryProvider).loadLlmSettingsBundle();
    if (!mounted) {
      return;
    }
    setState(() {
      _bundle = bundle;
      _draft = bundle.activeProvider;
      _applyDraftFields();
      _busy = false;
    });
  }

  void _applyDraftFields() {
    final c = _bundle.configFor(_draft);
    _baseUrl.text = c.baseUrl ?? '';
    _apiKey.text = c.apiKey ?? '';
    _model.text = c.model ?? '';
  }

  LlmEndpointConfig get _draftConfig => LlmEndpointConfig(
        baseUrl: _baseUrl.text.trim().isEmpty ? null : _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
        model: _model.text.trim().isEmpty ? null : _model.text.trim(),
      );

  void _select(LlmProvider p) {
    setState(() {
      _notice = null;
      // Tap selected draft again collapses to None.
      _draft = _draft == p ? LlmProvider.none : p;
      _applyDraftFields();
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final next = _bundle.persistEdit(
      draftProvider: _draft,
      draftConfig: _draftConfig,
    );
    final wantedActive = _draft;
    final activated = next.activeProvider == wantedActive ||
        wantedActive == LlmProvider.none;
    await ref.read(hostRepositoryProvider).saveLlmSettingsBundle(next);
    ref.invalidate(llmSettingsProvider);
    if (!mounted) {
      return;
    }
    if (!activated && wantedActive.enabled) {
      setState(() {
        _bundle = next;
        _busy = false;
        _notice =
            'Saved draft — complete base URL, model${wantedActive == LlmProvider.openaiCompatible ? ', and API key' : ''} to activate.';
      });
      return;
    }
    if (mounted) {
      setState(() => _busy = false);
      Navigator.of(context).pop();
    }
  }

  String? _pillFor(LlmProvider p) {
    if (_bundle.activeProvider == p) {
      if (p.enabled && !_bundle.configFor(p).isCompleteFor(p)) {
        return 'not configured';
      }
      return 'selected';
    }
    if (_draft == p && p.enabled && !_draftConfig.isCompleteFor(p)) {
      return 'not configured';
    }
    return null;
  }

  Widget _fieldsFor(LlmProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KelolaInput(
            label: 'Base URL',
            controller: _baseUrl,
            mono: true,
            hint: p == LlmProvider.ollama
                ? 'http://192.168.1.50:11434'
                : 'https://api.openai.com/v1',
          ),
          const SizedBox(height: 10),
          KelolaInput(
            label: 'Model',
            controller: _model,
            mono: true,
            hint: p == LlmProvider.ollama ? 'llama3.2' : 'gpt-4o-mini',
          ),
          if (p == LlmProvider.openaiCompatible) ...[
            const SizedBox(height: 10),
            KelolaInput(
              label: 'API key',
              controller: _apiKey,
              mono: true,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Text(
          'Assist',
          style: KelolaType.display(color: c.text, size: 16),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
        children: [
          Text(
            'PROVIDER',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 6),
          for (final p in LlmProvider.values) ...[
            ServiceRow(
              risk: RiskLevel.read,
              name: switch (p) {
                LlmProvider.none => 'None',
                LlmProvider.ollama => 'Ollama',
                LlmProvider.openaiCompatible => 'OpenAI-compatible',
              },
              meta: p == LlmProvider.none
                  ? 'default · no egress'
                  : p == LlmProvider.ollama
                      ? 'user URL · always redacted'
                      : 'user URL + key · preview once',
              pillText: _pillFor(p),
              onTap: _busy ? null : () => _select(p),
            ),
            if (_draft == p && p != LlmProvider.none) ...[
              const SizedBox(height: 8),
              _fieldsFor(p),
            ],
            const SizedBox(height: 6),
          ],
          if (_notice != null) ...[
            Text(
              _notice!,
              style: KelolaType.body(color: c.muted, size: 12),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          ServiceRow(
            risk: RiskLevel.mutate,
            name: 'Save',
            meta: 'keep on this device',
            onTap: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
