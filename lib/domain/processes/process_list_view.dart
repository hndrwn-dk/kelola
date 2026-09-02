import 'package:kelola/domain/processes/process_row.dart';

enum ProcessSort { cpu, memory, name }

List<ProcessRow> sortProcesses(List<ProcessRow> rows, ProcessSort sort) {
  final out = [...rows];
  switch (sort) {
    case ProcessSort.cpu:
      out.sort((a, b) => b.cpu.compareTo(a.cpu));
    case ProcessSort.memory:
      out.sort((a, b) => b.rssKb.compareTo(a.rssKb));
    case ProcessSort.name:
      out.sort(
        (a, b) => a.command.toLowerCase().compareTo(b.command.toLowerCase()),
      );
  }
  return out;
}

String formatProcessRss(int rssKb) {
  if (rssKb >= 1024 * 1024) {
    return '${(rssKb / (1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (rssKb >= 1024) {
    return '${(rssKb / 1024).toStringAsFixed(0)} MB';
  }
  return '$rssKb KB';
}

String formatProcessEtime(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t == '-') {
    return '';
  }
  var days = 0;
  var rest = t;
  final dash = t.split('-');
  if (dash.length == 2) {
    days = int.tryParse(dash[0]) ?? 0;
    rest = dash[1];
  }
  final parts = rest.split(':').map((s) => int.tryParse(s) ?? 0).toList();
  var hours = 0;
  var minutes = 0;
  var seconds = 0;
  if (parts.length == 3) {
    hours = parts[0];
    minutes = parts[1];
    seconds = parts[2];
  } else if (parts.length == 2) {
    minutes = parts[0];
    seconds = parts[1];
  } else if (parts.length == 1) {
    seconds = parts[0];
  }
  if (days > 0) {
    return '${days}d';
  }
  if (hours > 0) {
    return minutes > 0 ? '${hours}h${minutes}m' : '${hours}h';
  }
  if (minutes > 0) {
    return '${minutes}m';
  }
  return '${seconds}s';
}

String formatProcessCpu(double cpu) {
  return '${cpu.round()}%';
}

String processListMeta(ProcessRow row) {
  final bits = <String>['pid ${row.pid}', row.user];
  final age = formatProcessEtime(row.etime);
  if (age.isNotEmpty) {
    bits.add(age);
  }
  return bits.join(' · ');
}
