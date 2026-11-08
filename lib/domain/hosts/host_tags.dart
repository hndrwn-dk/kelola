import 'package:kelola/domain/hosts/host.dart';

/// Host tags are stored in this form, so every comparison uses it too.
String normalizeHostTag(String tag) => tag.trim().toLowerCase();

/// Tags from the Edit host field, in the order typed.
List<String> parseHostTags(String text) {
  return text
      .split(RegExp(r'[,;\s]+'))
      .map(normalizeHostTag)
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList();
}

/// [text] with [tag] added, or removed if it was already there.
String toggleHostTag(String text, String tag) {
  final tags = parseHostTags(text);
  final wanted = normalizeHostTag(tag);
  if (!tags.remove(wanted)) {
    tags.add(wanted);
  }
  return tags.join(', ');
}

/// Every tag in use, for offering instead of retyping.
List<String> knownHostTags(Iterable<Host> hosts) {
  return {for (final host in hosts) ...host.tags}.toList()..sort();
}
