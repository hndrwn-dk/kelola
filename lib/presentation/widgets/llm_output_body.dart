import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:markdown/markdown.dart' as md;

/// Strip common markdown markers for plain-text fallback.
String stripLlmMarkdown(String source) {
  var s = source;
  s = s.replaceAllMapped(
    RegExp(r'```[^\n]*\n([\s\S]*?)```'),
    (m) => m.group(1) ?? '',
  );
  s = s.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)'), (m) => m.group(1) ?? '');
  s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^[\*\-\+]\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '');
  return s.trim();
}

/// Shared renderer for untrusted LLM prose (Explain, Summarise, Assist result).
///
/// Subset: paragraphs, bold, lists, inline code, fenced code.
/// No link launching, no images, no raw HTML.
class LlmOutputBody extends StatelessWidget {
  const LlmOutputBody({
    super.key,
    required this.source,
    this.wrapSelection = true,
  });

  final String source;

  /// When false, caller owns [SelectionArea] (e.g. structured Explain).
  final bool wrapSelection;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final body = KelolaType.body(color: c.text, size: 13);
    final mono = KelolaType.mono(color: c.text, size: 11);
    final bold = KelolaType.body(
      color: c.text,
      size: 13,
      weight: FontWeight.w600,
    );

    try {
      // Fail closed: if the package cannot parse, strip and show plain text.
      md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      ).parse(source);

      final child = MarkdownBody(
        data: source,
        selectable: false,
        softLineBreak: true,
        shrinkWrap: true,
        fitContent: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        onTapLink: (text, href, title) {},
        imageBuilder: (uri, title, alt) => const SizedBox.shrink(),
        styleSheet: MarkdownStyleSheet(
          p: body,
          strong: bold,
          em: body,
          listBullet: body,
          a: body.copyWith(decoration: TextDecoration.none),
          code: mono.copyWith(
            backgroundColor: c.surface2,
          ),
          codeblockDecoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(KelolaRadii.sm),
            border: Border.all(color: c.line),
          ),
          codeblockPadding: const EdgeInsets.all(10),
          blockSpacing: 10,
          listIndent: 20,
          h1: bold,
          h2: bold,
          h3: bold,
          h4: bold,
          h5: bold,
          h6: bold,
        ),
        builders: {
          'img': _EmptyElementBuilder(),
          'html': _EmptyElementBuilder(),
        },
      );
      return wrapSelection ? SelectionArea(child: child) : child;
    } catch (_) {
      final child = Text(
        stripLlmMarkdown(source),
        style: body,
        softWrap: true,
        overflow: TextOverflow.visible,
      );
      return wrapSelection ? SelectionArea(child: child) : child;
    }
  }
}

class _EmptyElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return const SizedBox.shrink();
  }
}
