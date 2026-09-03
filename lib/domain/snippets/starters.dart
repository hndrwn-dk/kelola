import 'package:kelola/domain/snippets/snippet.dart';

const shippedSnippets = [
  Snippet(
    id: 'starter-status',
    name: 'status',
    template: 'systemctl status {{unit}} --no-pager',
    starter: true,
  ),
  Snippet(
    id: 'starter-listen',
    name: 'listen-on-port',
    template: r'ss -lptn | grep -F :{{port}}',
    starter: true,
  ),
  Snippet(
    id: 'starter-df',
    name: 'df -PT',
    template: 'df -PT {{path}}',
    starter: true,
  ),
  Snippet(
    id: 'starter-vacuum',
    name: 'vacuum-journal (proposed)',
    template: 'journalctl --vacuum-time=7d',
    starter: true,
  ),
];
