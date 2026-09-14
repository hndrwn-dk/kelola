import 'dart:convert';

import 'package:kelola/domain/probes/snippet_probe.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class Snippet {
  const Snippet({
    required this.id,
    required this.name,
    required this.template,
    this.starter = false,
  });

  final String id;
  final String name;
  final String template;
  final bool starter;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'template': template,
        'starter': starter,
      };

  factory Snippet.fromJson(Map<String, dynamic> json) {
    return Snippet(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      template: json['template'] as String? ?? '',
      starter: json['starter'] as bool? ?? false,
    );
  }
}

class SnippetBindings {
  const SnippetBindings({
    this.unit,
    this.path,
    this.port,
    this.host,
  });

  final String? unit;
  final String? path;
  final String? port;
  final String? host;
}

class SnippetUnboundException implements Exception {
  SnippetUnboundException(this.template);

  final String template;

  @override
  String toString() => 'Snippet still has placeholders: $template';
}

final _placeholder = RegExp(r'\{\{(unit|path|port|host)\}\}');

Set<String> snippetPlaceholders(String template) {
  return {
    for (final m in _placeholder.allMatches(template)) m.group(1)!,
  };
}

class SnippetRender {
  const SnippetRender({
    required this.commandLine,
    required this.emptyPlaceholders,
  });

  /// Null when a required placeholder is blank. Never a quoted empty argument.
  final String? commandLine;
  final Set<String> emptyPlaceholders;

  bool get canRun => commandLine != null;
}

String? _bindingValue(SnippetBindings bindings, String name) {
  return switch (name) {
    'unit' => bindings.unit,
    'path' => bindings.path,
    'port' => bindings.port,
    'host' => bindings.host,
    _ => null,
  };
}

/// One render for preview and execution. Static template text is unchanged.
/// Each placeholder value is POSIX single-quoted via [shellSingleQuote].
SnippetRender renderSnippet(String template, SnippetBindings bindings) {
  final needed = snippetPlaceholders(template);
  final empty = <String>{};
  final values = <String, String>{};
  for (final name in needed) {
    final raw = _bindingValue(bindings, name);
    if (raw == null || raw.trim().isEmpty) {
      empty.add(name);
      continue;
    }
    values[name] = raw;
  }
  if (empty.isNotEmpty) {
    return SnippetRender(commandLine: null, emptyPlaceholders: empty);
  }
  final line = template.replaceAllMapped(_placeholder, (match) {
    return shellSingleQuote(values[match.group(1)!]!);
  });
  return SnippetRender(commandLine: line, emptyPlaceholders: const {});
}

String expandSnippetTemplate(String template, SnippetBindings bindings) {
  final rendered = renderSnippet(template, bindings);
  final line = rendered.commandLine;
  if (line == null) {
    throw SnippetUnboundException(template);
  }
  return line;
}

SnippetProbe snippetToProbe(Snippet snippet, SnippetBindings bindings) {
  return SnippetProbe(
    name: snippet.name,
    commandLine: expandSnippetTemplate(snippet.template, bindings),
  );
}

String encodeSnippets(List<Snippet> items) {
  return jsonEncode(items.map((s) => s.toJson()).toList());
}

List<Snippet> decodeSnippets(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    return const [];
  }
  return [
    for (final item in decoded)
      if (item is Map) Snippet.fromJson(Map<String, dynamic>.from(item)),
  ];
}
