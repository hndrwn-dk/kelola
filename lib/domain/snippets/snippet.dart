import 'dart:convert';

import 'package:kelola/domain/probes/snippet_probe.dart';

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

String expandSnippetTemplate(String template, SnippetBindings bindings) {
  return template
      .replaceAll('{{unit}}', bindings.unit ?? '{{unit}}')
      .replaceAll('{{path}}', bindings.path ?? '{{path}}')
      .replaceAll('{{port}}', bindings.port ?? '{{port}}')
      .replaceAll('{{host}}', bindings.host ?? '{{host}}');
}

SnippetProbe snippetToProbe(Snippet snippet, SnippetBindings bindings) {
  final line = expandSnippetTemplate(snippet.template, bindings);
  if (_placeholder.hasMatch(line)) {
    throw SnippetUnboundException(line);
  }
  return SnippetProbe(name: snippet.name, commandLine: line);
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
