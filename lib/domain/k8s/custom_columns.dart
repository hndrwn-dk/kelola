/// `kubectl --output=custom-columns=` reads, which name the fields they
/// print. Kelola uses them through the read-only `kelola-reader` account
/// (M52e) so a read never prints a pod template, whose literal `env` values
/// often hold credentials.
library;

/// `--output=custom-columns=H:path,…`. Each header is one token and no path
/// holds a space.
String customColumnsOutput(List<(String, String)> columns) =>
    '--output=custom-columns='
    '${columns.map((c) => '${c.$1}:${c.$2}').join(',')}';

/// Whether [stdout] holds the header line of [columns].
bool hasCustomColumnsHeader(String stdout, List<(String, String)> columns) {
  final header = columns.map((c) => c.$1).join(' ');
  return stdout
      .split('\n')
      .any((l) => l.trim().split(RegExp(r'\s+')).join(' ') == header);
}

/// Rows of a `custom-columns` table with [columns], header lines (kubectl
/// prints one per kind) and blank lines left out. `<none>` reads as empty.
/// A line with another number of fields is dropped.
List<Map<String, String>> parseCustomColumns(
  String stdout,
  List<(String, String)> columns,
) {
  final header = columns.map((c) => c.$1).join(' ');
  final out = <Map<String, String>>[];
  for (final line in stdout.split('\n')) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.join(' ') == header || fields.length != columns.length) {
      continue;
    }
    out.add({
      for (var i = 0; i < columns.length; i++)
        columns[i].$1: fields[i] == '<none>' ? '' : fields[i],
    });
  }
  return out;
}

/// The workload list read through the reader (M52d, M52e). Only names, counts and
/// container states, never the pod template: `--output=json` of a workload
/// carries every literal `env` value, which often holds credentials. Each
/// column is one header letter and one path; no path or value holds a space.
const kWorkloadReaderColumns = [
  ('A', '.kind'),
  ('B', '.metadata.namespace'),
  ('C', '.metadata.name'),
  ('D', '.spec.replicas'),
  ('E', '.status.replicas'),
  ('F', '.status.readyReplicas'),
  ('G', '.status.desiredNumberScheduled'),
  ('H', '.status.numberReady'),
  ('I', '.spec.completions'),
  ('J', '.status.succeeded'),
  ('K', '.status.failed'),
  ('L', '.status.active[*].name'),
  ('M', '.status.phase'),
  ('N', '.status.containerStatuses[*].ready'),
  ('O', '.status.containerStatuses[*].restartCount'),
  ('P', '.status.containerStatuses[*].state.waiting.reason'),
  ('Q', '.status.containerStatuses[*].lastState.terminated.reason'),
  ('R', '.status.initContainerStatuses[*].restartCount'),
  ('S', '.status.initContainerStatuses[*].state.waiting.reason'),
];

/// `--output=custom-columns=…` for [kWorkloadReaderColumns].
final kWorkloadReaderOutput = customColumnsOutput(kWorkloadReaderColumns);

/// The pod list read through the reader (M52d, M52e). Namespace, name, phase and the
/// first image only: `--output=json` of a pod carries every literal `env`
/// value.
const kPodReaderColumns = [
  ('N', '.metadata.namespace'),
  ('P', '.metadata.name'),
  ('S', '.status.phase'),
  ('I', '.spec.containers[0].image'),
];

/// `--output=custom-columns=…` for [kPodReaderColumns].
final kPodReaderOutput = customColumnsOutput(kPodReaderColumns);
