import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/snippet_probe.dart';

enum ProbeScope { host, fleet }

class SnippetFleetForbidden implements Exception {
  @override
  String toString() => 'Snippets cannot run in fleet mode';
}

typedef SnippetExecute = Future<T> Function<T>(Host host, Probe<T> probe);

Future<T> runSnippet<T>({
  required Host host,
  required Probe<T> probe,
  required SnippetExecute execute,
  required ProbeScope scope,
}) async {
  if (scope == ProbeScope.fleet) {
    throw SnippetFleetForbidden();
  }
  if (probe is! SnippetProbe) {
    throw ArgumentError.value(probe, 'probe', 'must be a SnippetProbe');
  }
  return execute(host, probe);
}
