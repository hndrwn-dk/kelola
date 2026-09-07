// App-side parsing of Explain replies. Do not rely on model markdown styling.

enum ExplainKind { failedUnit, disk }

class ExplainSection {
  const ExplainSection({required this.title, required this.body});

  final String title;
  final String body;
}

class ParsedExplain {
  const ParsedExplain.structured(this.sections)
      : isStructured = true,
        fallback = null;

  const ParsedExplain.plain(this.fallback)
      : isStructured = false,
        sections = const [];

  final bool isStructured;
  final List<ExplainSection> sections;
  final String? fallback;
}

const _failedUnitLabels = [
  ('Cause', ['cause']),
  ('Concrete Error Line', [
    'concrete error line',
    'error line',
  ]),
  ('Next Step', ['next step']),
];

const _diskLabels = [
  ('What', ['what', 'what is large']),
  ('Evidence', ['evidence']),
  ('Next Step', ['next step']),
];

/// Parse labeled Explain sections. Only returns structured when at least one
/// known label has non-empty body. Never invents empty headings.
ParsedExplain parseExplainSections(
  String source, {
  required ExplainKind kind,
}) {
  final labels = kind == ExplainKind.failedUnit ? _failedUnitLabels : _diskLabels;
  final trimmed = source.trim();
  if (trimmed.isEmpty) {
    return ParsedExplain.plain(trimmed);
  }

  // Match a line that starts with a known section label (with optional
  // markdown heading/bold markers). Capture optional same-line body after `:`.
  final aliasPattern = labels
      .expand((e) => [e.$1.toLowerCase(), ...e.$2])
      .map(RegExp.escape)
      .toSet()
      .join('|');

  final headingRe = RegExp(
    '^'
    r'[ \t]*(?:#{1,6}[ \t]+|\d+\.[ \t]+)?'
    r'(?:\*{1,2}|_{1,2})?'
    '($aliasPattern)'
    r'(?:\*{1,2}|_{1,2})?'
    r'[ \t]*:'
    r'[ \t]*(.*)$',
    multiLine: true,
    caseSensitive: false,
  );

  final matches = headingRe.allMatches(source).toList();
  if (matches.isEmpty) {
    return ParsedExplain.plain(trimmed);
  }

  final found = <String, String>{};
  for (var i = 0; i < matches.length; i++) {
    final rawTitle = matches[i].group(1)!.trim();
    final key = _matchLabel(rawTitle, labels);
    if (key == null) {
      continue;
    }
    final sameLine = (matches[i].group(2) ?? '').trim();
    final start = matches[i].end;
    final end = i + 1 < matches.length ? matches[i + 1].start : source.length;
    final following = source.substring(start, end).trim();
    final body = [
      if (sameLine.isNotEmpty) sameLine,
      if (following.isNotEmpty) following,
    ].join('\n').trim();
    if (body.isEmpty) {
      continue;
    }
    found.putIfAbsent(key, () => body);
  }

  final sections = <ExplainSection>[
    for (final (title, _) in labels)
      if (found.containsKey(title))
        ExplainSection(title: title, body: found[title]!),
  ];

  if (sections.isEmpty) {
    return ParsedExplain.plain(trimmed);
  }
  return ParsedExplain.structured(sections);
}

String? _matchLabel(String rawTitle, List<(String, List<String>)> labels) {
  final norm = rawTitle.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final (canonical, aliases) in labels) {
    if (norm == canonical.toLowerCase()) {
      return canonical;
    }
    for (final a in aliases) {
      if (norm == a) {
        return canonical;
      }
    }
  }
  return null;
}
