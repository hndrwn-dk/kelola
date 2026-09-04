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
  LlmProvider _provider = LlmProvider.none;
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  bool _busy = true;

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
    final s = await ref.read(hostRepositoryProvider).loadLlmSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _provider = s.provider;
      _baseUrl.text = s.baseUrl ?? '';
      _apiKey.text = s.apiKey ?? '';
      _model.text = s.model ?? '';
      _busy = false;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await ref.read(hostRepositoryProvider).saveLlmSettings(
          LlmSettings(
            provider: _provider,
            baseUrl: _baseUrl.text.trim().isEmpty ? null : _baseUrl.text.trim(),
            apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
            model: _model.text.trim().isEmpty ? null : _model.text.trim(),
          ),
        );
    ref.invalidate(llmSettingsProvider);
    if (mounted) {
      setState(() => _busy = false);
      Navigator.of(context).pop();
    }
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
              pillText: _provider == p ? 'selected' : null,
              onTap: _busy ? null : () => setState(() => _provider = p),
            ),
            const SizedBox(height: 6),
          ],
          if (_provider != LlmProvider.none) ...[
            const SizedBox(height: 8),
            KelolaInput(
              label: 'Base URL',
              controller: _baseUrl,
              mono: true,
              hint: _provider == LlmProvider.ollama
                  ? 'http://192.168.1.50:11434'
                  : 'https://api.example.com',
            ),
            const SizedBox(height: 10),
            KelolaInput(
              label: 'Model',
              controller: _model,
              mono: true,
              hint: _provider == LlmProvider.ollama ? 'llama3.2' : 'gpt-4o-mini',
            ),
            if (_provider == LlmProvider.openaiCompatible) ...[
              const SizedBox(height: 10),
              KelolaInput(
                label: 'API key',
                controller: _apiKey,
                mono: true,
              ),
            ],
          ],
          const SizedBox(height: 16),
          ServiceRow(
            risk: RiskLevel.mutate,
            name: 'Save',
            meta: 'no Tursina endpoint',
            onTap: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
