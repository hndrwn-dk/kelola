import 'package:kelola/app_version.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/redaction/redact.dart';

String buildDiagnosticPack({
  required Host host,
  required HostFacts facts,
  required List<String> failedUnits,
  required List<JournalEntry> journal,
  required String dfPt,
  String appVersion = kelolaAppVersion,
  String flutterVersion = kelolaFlutterVersion,
}) {
  final buf = StringBuffer();
  buf.writeln('## hostfacts');
  buf.writeln(_factsBlock(facts));
  buf.writeln('## attention');
  buf.writeln('attention: ${host.attention.name}');
  if (host.failedUnitCount != null) {
    buf.writeln('failed_unit_count: ${host.failedUnitCount}');
  }
  if (host.diskRootPercent != null) {
    buf.writeln('disk_root_percent: ${host.diskRootPercent}');
  }
  buf.writeln('## failed units');
  if (failedUnits.isEmpty) {
    buf.writeln('(none)');
  } else {
    for (final u in failedUnits) {
      buf.writeln(u);
    }
  }
  buf.writeln('## journal');
  final lines = journal.take(50).toList();
  if (lines.isEmpty) {
    buf.writeln('(none)');
  } else {
    for (final e in lines) {
      final unit = (e.unit ?? '').trim();
      final prefix = unit.isEmpty ? '' : '$unit ';
      buf.writeln('$prefix${e.message}');
    }
  }
  buf.writeln('## df -PT');
  final df = dfPt.trim();
  buf.writeln(df.isEmpty ? '(none)' : df);
  buf.writeln('## kelola');
  buf.writeln('kelola: $appVersion');
  buf.writeln('flutter: $flutterVersion');
  return redactText(
    buf.toString(),
    hostnames: [
      host.alias,
      host.address,
      if (host.prettyName != null) host.prettyName!,
    ],
    usernames: [host.username],
  );
}

String _factsBlock(HostFacts facts) {
  final lines = <String>[
    'os: ${facts.osId} ${facts.osVersionId}'.trimRight(),
    if (facts.prettyName != null && facts.prettyName!.isNotEmpty)
      'pretty: ${facts.prettyName}',
    'init: ${facts.init.name}',
    if (facts.systemdVersion != null) 'systemd: ${facts.systemdVersion}',
    'pkg: ${facts.pkg.name}',
    'fw: ${facts.fw.name}',
    'arch: ${facts.arch}',
    if (facts.nprocCores != null) 'cores: ${facts.nprocCores}',
    'journald: ${facts.hasJournald} readable=${facts.journalReadable}',
    if (facts.runtimes.isNotEmpty) 'runtimes: ${facts.runtimes.join(',')}',
    if (facts.model != null && facts.model!.isNotEmpty) 'model: ${facts.model}',
    if (facts.virt != null && facts.virt!.isNotEmpty) 'virt: ${facts.virt}',
  ];
  for (final n in facts.nics) {
    final bits = <String>['nic ${n.name}'];
    if (n.mac != null && n.mac!.isNotEmpty) {
      bits.add('mac=${n.mac}');
    }
    if (n.ipv4 != null && n.ipv4!.isNotEmpty) {
      bits.add('ipv4=${n.ipv4}');
    }
    if (n.ipv6 != null && n.ipv6!.isNotEmpty) {
      bits.add('ipv6=${n.ipv6}');
    }
    lines.add(bits.join(' '));
  }
  return lines.join('\n');
}
