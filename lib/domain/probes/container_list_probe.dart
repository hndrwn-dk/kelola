import 'package:kelola/domain/containers/container_list_parser.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class ContainerListProbe extends Probe<ContainerInventory> {
  const ContainerListProbe();

  @override
  String get auditTitle => 'Listed containers';

  @override
  String command(HostFacts facts) {
    return r'''
LC_ALL=C
echo "---ENGINE---"
command -v k3s kubectl docker podman crictl nerdctl 2>/dev/null || true
echo "---PODS---"
if command -v k3s >/dev/null 2>&1; then
  sudo -n k3s kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
    || k3s kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
    || true
elif command -v kubectl >/dev/null 2>&1; then
  kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
    || sudo -n kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
    || true
fi
echo "---PS---"
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    docker ps -a --format '{{json .}}'
  elif sudo -n docker info >/dev/null 2>&1; then
    sudo -n docker ps -a --format '{{json .}}'
  else
    echo "---DOCKER_DENIED---"
  fi
elif command -v podman >/dev/null 2>&1; then
  podman ps -a --format json 2>/dev/null || sudo -n podman ps -a --format json 2>/dev/null || true
elif command -v crictl >/dev/null 2>&1; then
  sudo -n crictl ps -a --output json 2>/dev/null || crictl ps -a --output json 2>/dev/null || true
elif command -v k3s >/dev/null 2>&1; then
  sudo -n k3s crictl ps -a --output json 2>/dev/null || true
fi
''';
  }

  @override
  ContainerInventory parse(String stdout, String stderr, int exitCode) {
    return const ContainerListParser().parse(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 25);
}
