import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/llm/api_key_hint.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';
import 'package:kelola/presentation/widgets/llm_api_key_field.dart';
import 'package:kelola/providers.dart';

class LlmSettingsScreen extends ConsumerStatefulWidget {
  const LlmSettingsScreen({super.key});

  @override
  ConsumerState<LlmSettingsScreen> createState() => _LlmSettingsScreenState();
}

class _LlmSettingsScreenState extends ConsumerState<LlmSettingsScreen> {
  /// Endpoint slots without secrets — the full API key never lives here.
  LlmSettingsBundle _bundle = const LlmSettingsBundle();
  LlmProvider _draft = LlmProvider.none;
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  String? _apiKeyHint;
  String? _draftApiKey;
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
    _model.dispose();
    super.dispose();
  }

  LlmSettingsBundle _stripSecrets(LlmSettingsBundle bundle) {
    return LlmSettingsBundle(
      activeProvider: bundle.activeProvider,
      ollama: bundle.ollama,
      openaiCompatible: LlmEndpointConfig(
        baseUrl: bundle.openaiCompatible.baseUrl,
        model: bundle.openaiCompatible.model,
      ),
    );
  }

  Future<void> _load() async {
    final repo = ref.read(hostRepositoryProvider);
    final bundle = await repo.loadLlmSettingsBundle();
    final hint = await repo.apiKeyHint(LlmProvider.openaiCompatible);
    if (!mounted) {
      return;
    }
    setState(() {
      _bundle = _stripSecrets(bundle);
      _draft = bundle.activeProvider;
      _apiKeyHint = hint;
      _draftApiKey = null;
      _applyDraftFields();
      _busy = false;
    });
  }

  void _applyDraftFields() {
    final c = _bundle.configFor(_draft);
    _baseUrl.text = c.baseUrl ?? '';
    _model.text = c.model ?? '';
    _draftApiKey = null;
  }

  bool get _openaiKeyPresent =>
      (_apiKeyHint != null && _apiKeyHint!.isNotEmpty) ||
      (_draftApiKey != null && _draftApiKey!.isNotEmpty);

  LlmEndpointConfig get _draftConfig {
    final base = _baseUrl.text.trim().isEmpty ? null : _baseUrl.text.trim();
    final model = _model.text.trim().isEmpty ? null : _model.text.trim();
    if (_draft != LlmProvider.openaiCompatible) {
      return LlmEndpointConfig(baseUrl: base, model: model);
    }
    return LlmEndpointConfig(
      baseUrl: base,
      model: model,
      // Presence token for completeness only — never a real secret.
      apiKey: _openaiKeyPresent ? 'present' : null,
    );
  }

  void _select(LlmProvider p) {
    setState(() {
      _notice = null;
      _draft = _draft == p ? LlmProvider.none : p;
      _applyDraftFields();
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final wantedActive = _draft;
    final settingNewKey = _draft == LlmProvider.openaiCompatible &&
        _draftApiKey != null &&
        _draftApiKey!.isNotEmpty;
    final write =
        settingNewKey ? LlmApiKeyWrite.set : LlmApiKeyWrite.keep;
    final next = _bundle.persistEdit(
      draftProvider: _draft,
      draftConfig: _draftConfig,
    );
    final bundle = LlmSettingsBundle(
      activeProvider: next.activeProvider,
      ollama: next.ollama,
      openaiCompatible: LlmEndpointConfig(
        baseUrl: next.openaiCompatible.baseUrl,
        model: next.openaiCompatible.model,
        apiKey: settingNewKey ? _draftApiKey : null,
      ),
    );
    final activated = bundle.activeProvider == wantedActive ||
        wantedActive == LlmProvider.none;
    await ref.read(hostRepositoryProvider).saveLlmSettingsBundle(
          bundle,
          apiKeyWrite: write,
        );
    ref.invalidate(llmSettingsProvider);
    if (!mounted) {
      return;
    }
    if (!activated && wantedActive.enabled) {
      final hint = await ref
          .read(hostRepositoryProvider)
          .apiKeyHint(LlmProvider.openaiCompatible);
      if (!mounted) {
        return;
      }
      setState(() {
        _bundle = _stripSecrets(bundle);
        _apiKeyHint = hint;
        _draftApiKey = null;
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
      if (p == LlmProvider.openaiCompatible) {
        final c = _bundle.configFor(p);
        final complete = c.hasValidBaseUrlFor(p) &&
            (c.model?.trim().isNotEmpty ?? false) &&
            _openaiKeyPresent;
        if (p.enabled && !complete) {
          return 'set up';
        }
      } else if (p.enabled && !_bundle.configFor(p).isCompleteFor(p)) {
        return 'set up';
      }
      return 'selected';
    }
    if (_draft == p && p.enabled && !_draftConfig.isCompleteFor(p)) {
      return 'set up';
    }
    return null;
  }

  Future<void> _onReplaceKey(String trimmed) async {
    await ref.read(hostRepositoryProvider).replaceOpenaiApiKey(trimmed);
    final hint = await ref
        .read(hostRepositoryProvider)
        .apiKeyHint(LlmProvider.openaiCompatible);
    if (!mounted) {
      return;
    }
    setState(() {
      _apiKeyHint = hint;
      _draftApiKey = null;
    });
    ref.invalidate(llmSettingsProvider);
  }

  Future<void> _onRemoveKey() async {
    await ref.read(hostRepositoryProvider).removeOpenaiApiKey();
    var next = _bundle;
    if (next.activeProvider == LlmProvider.openaiCompatible) {
      next = LlmSettingsBundle(
        activeProvider: LlmProvider.none,
        ollama: next.ollama,
        openaiCompatible: next.openaiCompatible,
      );
      await ref.read(hostRepositoryProvider).saveLlmSettingsBundle(
            next,
            apiKeyWrite: LlmApiKeyWrite.keep,
          );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _bundle = next;
      _apiKeyHint = null;
      _draftApiKey = null;
    });
    ref.invalidate(llmSettingsProvider);
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
            LlmApiKeyField(
              storedHint: _apiKeyHint,
              onReplace: _onReplaceKey,
              onRemove: _onRemoveKey,
              onDraftChanged: (value) {
                setState(() => _draftApiKey = value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              'HTTPS required. HTTP is only allowed on localhost.',
              style: KelolaType.body(color: context.kc.dim, size: 12),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return KelolaWashScaffold(
      appBar: AppBar(
        backgroundColor: c.ink.withValues(alpha: 0),
        surfaceTintColor: c.ink.withValues(alpha: 0),
        forceMaterialTransparency: true,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'AI Assist',
          style: KelolaType.display(color: c.text, size: 16),
        ),
      ),
      body: ListView(
        padding: kelolaScrollPadding(context),
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
