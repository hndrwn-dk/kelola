import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/domain/probes/snippet_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/snippets/run_snippet.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/domain/snippets/snippet_scope.dart';

enum SnippetMultiStatus { ran, skipped, unbound, failed }

class SnippetMultiPreview {
  const SnippetMultiPreview({
    required this.host,
    required this.commandLine,
  });

  final Host host;
  final String? commandLine;
}

class SnippetMultiOutcome {
  const SnippetMultiOutcome({
    required this.hostId,
    required this.alias,
    required this.status,
    this.output,
    this.error,
  });

  final String hostId;
  final String alias;
  final SnippetMultiStatus status;
  final String? output;
  final String? error;
}

List<Host> planSnippetMultiHosts(Snippet snippet, List<Host> hosts) {
  return [
    for (final host in hosts)
      if (snippetAppliesToHost(snippet, host)) host,
  ];
}

SnippetBindings snippetMultiBindings(Host host, SnippetBindings shared) {
  return SnippetBindings(
    unit: shared.unit,
    path: shared.path,
    port: shared.port,
    host: host.alias,
  );
}

List<SnippetMultiPreview> previewSnippetMulti({
  required Snippet snippet,
  required List<Host> hosts,
  required SnippetBindings shared,
}) {
  return [
    for (final host in hosts)
      SnippetMultiPreview(
        host: host,
        commandLine: renderSnippet(
          snippet.template,
          snippetMultiBindings(host, shared),
        ).commandLine,
      ),
  ];
}

Future<List<SnippetMultiOutcome>> runSnippetMulti({
  required Snippet snippet,
  required List<Host> hosts,
  required SnippetBindings shared,
  required SnippetExecute execute,
  required Future<bool> Function(Host host, SnippetProbe probe) confirm,
}) async {
  final outcomes = <SnippetMultiOutcome>[];
  for (final host in hosts) {
    late final SnippetProbe probe;
    try {
      probe = snippetToProbe(snippet, snippetMultiBindings(host, shared));
    } on SnippetUnboundException {
      outcomes.add(
        SnippetMultiOutcome(
          hostId: host.id,
          alias: host.alias,
          status: SnippetMultiStatus.unbound,
          error: 'unbound',
        ),
      );
      continue;
    }
    if (probe.risk != RiskLevel.read) {
      if (!await confirm(host, probe)) {
        outcomes.add(
          SnippetMultiOutcome(
            hostId: host.id,
            alias: host.alias,
            status: SnippetMultiStatus.skipped,
          ),
        );
        continue;
      }
    }
    try {
      final result = await runSnippet<CommandRunnerResult>(
        host: host,
        probe: probe,
        execute: execute,
        scope: ProbeScope.host,
      );
      outcomes.add(
        SnippetMultiOutcome(
          hostId: host.id,
          alias: host.alias,
          status: SnippetMultiStatus.ran,
          output: formatCommandRun(probe.commandLine, result),
        ),
      );
    } catch (e) {
      outcomes.add(
        SnippetMultiOutcome(
          hostId: host.id,
          alias: host.alias,
          status: SnippetMultiStatus.failed,
          error: e.toString(),
        ),
      );
    }
  }
  return outcomes;
}
