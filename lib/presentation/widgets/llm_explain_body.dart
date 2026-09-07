import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/llm/explain_sections.dart';
import 'package:kelola/presentation/widgets/llm_output_body.dart';

/// Explain output: app-owned section headings + markdown bodies.
/// Falls back to [LlmOutputBody] when sections are not recognisable.
class LlmExplainBody extends StatelessWidget {
  const LlmExplainBody({
    super.key,
    required this.source,
    required this.kind,
  });

  final String source;
  final ExplainKind kind;

  @override
  Widget build(BuildContext context) {
    final parsed = parseExplainSections(source, kind: kind);
    if (!parsed.isStructured) {
      return LlmOutputBody(source: parsed.fallback ?? source);
    }

    final c = context.kc;
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < parsed.sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Text(
              parsed.sections[i].title.toUpperCase(),
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
            const SizedBox(height: 6),
            LlmOutputBody(
              source: parsed.sections[i].body,
              wrapSelection: false,
            ),
          ],
        ],
      ),
    );
  }
}
