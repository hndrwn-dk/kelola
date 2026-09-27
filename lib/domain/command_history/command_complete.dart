const kCommandCompleteCap = 8;

const kCommandCompleteCorpus = [
  'uptime',
  'df -PT',
  'df -h',
  'free -h',
  'uname -a',
  'whoami',
  'id',
  'hostnamectl',
  'systemctl status',
  'systemctl list-units --failed',
  'systemctl restart',
  'journalctl -u',
  'journalctl -xe',
  'ss -lptn',
  'ip -br addr',
  'docker ps',
  'ls -la',
  'cat',
  'tail -n 50',
  'grep -n',
  'du -sh',
  'ps aux',
];

List<String> completeCommandLines({
  required String query,
  required List<String> history,
  List<String> corpus = kCommandCompleteCorpus,
  int cap = kCommandCompleteCap,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty || cap <= 0) {
    return const [];
  }
  final out = <String>[];
  final seen = <String>{};

  void consider(String line, bool Function(String line) match) {
    if (out.length >= cap || !match(line) || !seen.add(line)) {
      return;
    }
    out.add(line);
  }

  bool prefix(String line) => line.toLowerCase().startsWith(q);
  bool substring(String line) => line.toLowerCase().contains(q);

  for (final line in history) {
    consider(line, prefix);
  }
  for (final line in history) {
    consider(line, substring);
  }
  for (final line in corpus) {
    consider(line, prefix);
  }
  for (final line in corpus) {
    consider(line, substring);
  }
  return out;
}
