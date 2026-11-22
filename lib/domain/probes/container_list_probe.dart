import 'package:kelola/domain/containers/container_engine.dart';
import 'package:kelola/domain/containers/container_list_parser.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/custom_columns.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class ContainerListProbe extends Probe<ContainerInventory> {
  const ContainerListProbe();

  @override
  String get auditTitle => 'Listed containers';

  @override
  String command(HostFacts facts) {
    return (r'''
LC_ALL=C
echo "---ENGINE---"
command -v k3s kubectl oc docker podman crictl nerdctl 2>/dev/null || true
[ -x "$HOME/.crc/bin/oc/oc" ] && echo "$HOME/.crc/bin/oc/oc"
echo "---PODS---"
# M48 precedence oc -> k3s -> kubectl. CRC keeps oc off PATH.
# M52e: through the kelola-reader kubeconfig, named columns only (pod
# JSON carries every env value); the parser reads both.
oc_bin=$(command -v oc 2>/dev/null || { [ -x "$HOME/.crc/bin/oc/oc" ] && echo "$HOME/.crc/bin/oc/oc"; })
if [ -n "$oc_bin" ]; then
  echo "cli=oc"
  "$oc_bin" get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null || sudo -n "$oc_bin" get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null || true
elif command -v k3s >/dev/null 2>&1; then
  echo "cli=k3s"
  { [ -r "$HOME/.kube/kelola.yaml" ] && k3s kubectl --kubeconfig="$HOME/.kube/kelola.yaml" get pods --all-namespaces __KELOLA_POD_COLUMNS__ 2>/dev/null; } || sudo -n k3s kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null || k3s kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null || true
elif command -v kubectl >/dev/null 2>&1; then
  echo "cli=kubectl"
  { [ -r "$HOME/.kube/kelola.yaml" ] && kubectl --kubeconfig="$HOME/.kube/kelola.yaml" get pods --all-namespaces __KELOLA_POD_COLUMNS__ 2>/dev/null; } || kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null || sudo -n kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null || true
fi
echo "---PS_DOCKER---"
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    docker ps -a --format '{{json .}}'
  elif sudo -n docker info >/dev/null 2>&1; then
    sudo -n docker ps -a --format '{{json .}}'
  else
    echo "---DOCKER_DENIED---"
  fi
fi
echo "---PS_PODMAN---"
user_ok=0
root_ok=0
sock_ok=0
sock=/run/podman/podman.sock
if command -v podman >/dev/null 2>&1; then
  ''' +
        podmanUserSession +
        r'''
  if user_json=$(podman ps -a --format json 2>/dev/null); then
    user_ok=1
    printf '%s\n' "$user_json"
  fi
fi
echo "---PS_PODMAN_SOCK---"
if command -v podman >/dev/null 2>&1 && [ -S "$sock" ] && [ -r "$sock" ]; then
  if sock_json=$(podman --remote --url "unix://$sock" ps -a --format json 2>/dev/null); then
    sock_ok=1
    printf '%s\n' "$sock_json"
  fi
fi
echo "---PS_PODMAN_ROOT---"
if command -v podman >/dev/null 2>&1; then
  if root_json=$(sudo -n podman ps -a --format json 2>/dev/null); then
    root_ok=1
    printf '%s\n' "$root_json"
  fi
  if [ -S "$sock" ] && [ ! -r "$sock" ] && [ "$sock_ok" -eq 0 ] && [ "$root_ok" -eq 0 ]; then
    echo "---PODMAN_SOCK_DENIED---"
  elif [ "$user_ok" -eq 0 ] && [ "$root_ok" -eq 0 ] && [ "$sock_ok" -eq 0 ]; then
    echo "---PODMAN_DENIED---"
  fi
fi
echo "---PS---"
''')
        .replaceAll('\r\n', '\n')
        .replaceAll('__KELOLA_POD_COLUMNS__', shellSingleQuote(kPodReaderOutput));
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
