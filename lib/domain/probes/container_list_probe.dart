import 'package:kelola/domain/containers/container_list_parser.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class ContainerListProbe extends Probe<List<ContainerRow>> {
  const ContainerListProbe();

  @override
  String command(HostFacts facts) {
    return r'''
LC_ALL=C
echo "---ENGINE---"
if command -v docker >/dev/null 2>&1; then echo docker
elif command -v podman >/dev/null 2>&1; then echo podman
else echo none
fi
echo "---PS---"
if command -v docker >/dev/null 2>&1; then
  docker ps -a --format '{{json .}}' 2>/dev/null || true
elif command -v podman >/dev/null 2>&1; then
  podman ps -a --format json 2>/dev/null || true
fi
''';
  }

  @override
  List<ContainerRow> parse(String stdout, String stderr, int exitCode) {
    return const ContainerListParser().parse(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 20);
}
