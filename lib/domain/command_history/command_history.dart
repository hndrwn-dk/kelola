const kCommandHistoryCap = 200;

const commandHistoryEmptyCopy = 'No commands on this host yet';

const commandHistoryNoMatchCopy = 'No matching commands';

String normalizeCommandHistoryLine(String raw) => raw.trim();

bool shouldRecordCommandHistory(String raw) =>
    normalizeCommandHistoryLine(raw).isNotEmpty;

List<String> filterCommandHistory(List<String> commands, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return List<String>.from(commands);
  }
  return commands.where((c) => c.toLowerCase().contains(q)).toList();
}
