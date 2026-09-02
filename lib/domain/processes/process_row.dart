class ProcessRow {
  const ProcessRow({
    required this.pid,
    required this.ppid,
    required this.user,
    required this.cpu,
    required this.mem,
    required this.rssKb,
    this.etime = '',
    required this.stat,
    required this.command,
  });

  final int pid;
  final int ppid;
  final String user;
  final double cpu;
  final double mem;
  final int rssKb;
  final String etime;
  final String stat;
  final String command;
}

class ProcessListParser {
  const ProcessListParser();

  List<ProcessRow> parse(String stdout) {
    final out = <ProcessRow>[];
    final withEtime = RegExp(
      r'^\s*(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.*)$',
    );
    final withoutEtime = RegExp(
      r'^\s*(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(.*)$',
    );
    for (final line in stdout.split('\n')) {
      final wide = withEtime.firstMatch(line);
      final etimeToken = wide?.group(7);
      final hasEtime = etimeToken != null &&
          (etimeToken.contains(':') || etimeToken.contains('-'));
      final m = hasEtime ? wide : withoutEtime.firstMatch(line);
      if (m == null) {
        continue;
      }
      final pid = int.tryParse(m.group(1)!);
      if (pid == null) {
        continue;
      }
      out.add(
        ProcessRow(
          pid: pid,
          ppid: int.tryParse(m.group(2)!) ?? 0,
          user: m.group(3)!,
          cpu: double.tryParse(m.group(4)!) ?? 0,
          mem: double.tryParse(m.group(5)!) ?? 0,
          rssKb: int.tryParse(m.group(6)!) ?? 0,
          etime: hasEtime ? m.group(7)! : '',
          stat: hasEtime ? m.group(8)! : m.group(7)!,
          command: (hasEtime ? m.group(9)! : m.group(8)!).trim(),
        ),
      );
    }
    return out;
  }
}
