import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/snippets/snippet.dart';

bool snippetAppliesToHost(Snippet snippet, Host host) {
  final hostId = snippet.hostId;
  if (hostId != null && hostId.isNotEmpty) {
    return hostId == host.id;
  }
  final tag = snippet.tag?.trim();
  if (tag != null && tag.isNotEmpty) {
    return host.tags.contains(tag);
  }
  return true;
}

List<Snippet> snippetsForHost(List<Snippet> all, Host host) {
  return [
    for (final snippet in all)
      if (snippetAppliesToHost(snippet, host)) snippet,
  ];
}

List<Snippet> startupSnippetsForHost(List<Snippet> all, Host host) {
  return [
    for (final snippet in snippetsForHost(all, host))
      if (snippet.startup) snippet,
  ];
}

String snippetScopeMeta(Snippet snippet) {
  final scope = () {
    final hostId = snippet.hostId;
    if (hostId != null && hostId.isNotEmpty) {
      return 'this host';
    }
    final tag = snippet.tag?.trim();
    if (tag != null && tag.isNotEmpty) {
      return 'tag $tag';
    }
    return snippet.starter ? 'starter' : 'all hosts';
  }();
  if (snippet.startup) {
    return 'startup · $scope · tap to run';
  }
  return '$scope · tap to run';
}
