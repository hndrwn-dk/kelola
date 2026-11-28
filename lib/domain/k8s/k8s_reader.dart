/// M52e: a read-only Kubernetes ServiceAccount for Kelola's reads.
///
/// Enable Kelola sudo creates, with the cluster's admin credentials and the
/// sudo password it already asked for:
/// - Namespace [kelolaReaderNamespace],
/// - ServiceAccount [kelolaReaderName] in it,
/// - ClusterRole [kelolaReaderName] with [kelolaReaderRules] (`get` and
///   `list` only),
/// - ClusterRoleBinding [kelolaReaderName] from the role to the account.
///
/// Then it asks the TokenRequest API for a token that lasts
/// [kelolaReaderTokenDuration] and writes it into [kelolaReaderKubeconfigPath]
/// (mode 0600, owned by the login). Kelola's Kubernetes reads use that
/// kubeconfig first ([kubectlRead]); mutating actions never do.
///
/// Least privilege (Kubernetes RBAC good practice, CIS Kubernetes Benchmark
/// 5.1): a custom role rather than the built-in `view`, only the resources
/// Kelola's screens read, no `watch`, no wildcard, and never Secrets,
/// ConfigMaps, `pods/exec`, `pods/attach`, `pods/portforward`, `nodes/proxy`
/// or `serviceaccounts/token`. No legacy never-expiring Secret token.
///
/// RBAC cannot hide fields, so the role's `list` on pods and workloads
/// returns pod specs with any literal `env` values. Kelola itself asks the
/// reader only for named columns (`kWorkloadReaderColumns`,
/// `kPodReaderColumns`); describe, YAML and rollout history keep using the
/// login's own kubeconfig, which is why the role has no ReplicaSets or
/// ControllerRevisions. Credentials belong in Secrets (`secretKeyRef`).
library;

import 'dart:convert';

import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';

const kelolaReaderNamespace = 'kelola';
const kelolaReaderName = 'kelola-reader';

/// The labels every object carries. Removal deletes by these, so it never
/// touches an object Kelola did not create.
const kelolaReaderLabels = {
  'app.kubernetes.io/name': kelolaReaderName,
  'app.kubernetes.io/managed-by': 'kelola',
};

/// `kubectl create token --duration`: 90 days. The API server may cap it
/// lower (`--service-account-max-token-expiration`); the script records the
/// expiry the server actually granted.
const kelolaReaderTokenDuration = '2160h';
const kelolaReaderTokenDays = 90;

/// The reader kubeconfig, relative to the login's home.
const kelolaReaderKubeconfigPath = '~/.kube/kelola.yaml';

/// [kelolaReaderKubeconfigPath] as a double-quoted shell word.
const kelolaReaderKubeconfig = r'"$HOME/.kube/kelola.yaml"';

/// The only verbs the role grants. Kelola never watches.
const kelolaReaderVerbs = ['get', 'list'];

class K8sRbacRule {
  const K8sRbacRule(this.apiGroups, this.resources);

  final List<String> apiGroups;
  final List<String> resources;

  List<String> get verbs => kelolaReaderVerbs;
}

/// What the role may read, and why:
/// - nodes, namespaces: cluster band, node list.
/// - events (core and `events.k8s.io`): Events, per-workload events.
/// - services, endpoints, endpointslices: Networking.
/// - persistentvolumes, persistentvolumeclaims: Storage.
/// - pods, `pods/log`, deployments, statefulsets, daemonsets, jobs,
///   cronjobs: workload and pod lists (named columns only) and logs.
/// - serviceaccounts, networkpolicies, clusterrolebindings: Security.
/// - `metrics.k8s.io` pods and nodes: top.
/// - `argoproj.io` applications, applicationsets, appprojects: GitOps (M49).
///   Application specs can carry inline Helm values; Kelola's parser drops
///   them (`lib/domain/argocd/`).
const kelolaReaderRules = [
  K8sRbacRule(
    [''],
    [
      'nodes',
      'namespaces',
      'events',
      'services',
      'endpoints',
      'persistentvolumes',
      'persistentvolumeclaims',
      'pods',
      'pods/log',
      'serviceaccounts',
    ],
  ),
  K8sRbacRule(['events.k8s.io'], ['events']),
  K8sRbacRule(['discovery.k8s.io'], ['endpointslices']),
  K8sRbacRule(['apps'], ['deployments', 'statefulsets', 'daemonsets']),
  K8sRbacRule(['batch'], ['jobs', 'cronjobs']),
  K8sRbacRule(['networking.k8s.io'], ['networkpolicies']),
  K8sRbacRule(['rbac.authorization.k8s.io'], ['clusterrolebindings']),
  K8sRbacRule(['metrics.k8s.io'], ['pods', 'nodes']),
  K8sRbacRule(
    ['argoproj.io'],
    ['applications', 'applicationsets', 'appprojects'],
  ),
];

/// Resources the role must never name, whatever the group.
const kelolaReaderForbiddenResources = {
  'secrets',
  'configmaps',
  'pods/exec',
  'pods/attach',
  'pods/portforward',
  'pods/proxy',
  'services/proxy',
  'nodes/proxy',
  'serviceaccounts/token',
  'replicasets',
  'controllerrevisions',
  '*',
};

String _yamlList(List<String> items) =>
    '[${items.map((s) => '"$s"').join(', ')}]';

String _labels(String indent) =>
    [for (final e in kelolaReaderLabels.entries) '$indent${e.key}: ${e.value}']
        .join('\n');

/// The four objects as one multi-document manifest for `kubectl apply`.
String kelolaReaderManifest() {
  final rules = [
    for (final r in kelolaReaderRules)
      '- apiGroups: ${_yamlList(r.apiGroups)}\n'
          '  resources: ${_yamlList(r.resources)}\n'
          '  verbs: ${_yamlList(r.verbs)}',
  ].join('\n');
  return '''
apiVersion: v1
kind: Namespace
metadata:
  name: $kelolaReaderNamespace
  labels:
${_labels('    ')}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $kelolaReaderName
  namespace: $kelolaReaderNamespace
  labels:
${_labels('    ')}
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $kelolaReaderName
  labels:
${_labels('    ')}
rules:
$rules
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $kelolaReaderName
  labels:
${_labels('    ')}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $kelolaReaderName
subjects:
- kind: ServiceAccount
  name: $kelolaReaderName
  namespace: $kelolaReaderNamespace
''';
}

/// One line per rule for the review sheet: `apps: deployments, …`.
List<String> kelolaReaderRuleLines() => [
  for (final r in kelolaReaderRules)
    '${r.apiGroups.map((g) => g.isEmpty ? 'core' : g).join(', ')}: '
        '${r.resources.join(', ')}',
];

/// The objects Enable Kelola sudo applies, as the review sheet lists them.
const kelolaReaderObjectLines = [
  'Namespace $kelolaReaderNamespace',
  'ServiceAccount $kelolaReaderNamespace/$kelolaReaderName',
  'ClusterRole $kelolaReaderName (get, list)',
  'ClusterRoleBinding $kelolaReaderName',
];

/// Whether this host's Kubernetes CLI gets a reader. `oc` logins are the
/// user's own OpenShift session, so they keep today's behaviour.
bool kelolaReaderSupported(KubectlFlavor flavor) =>
    flavor == KubectlFlavor.k3s || flavor == KubectlFlavor.kubectl;

/// Root-owned admin kubeconfigs the setup may use through sudo, in order.
List<String> kelolaReaderAdminConfigs(KubectlFlavor flavor) => switch (flavor) {
  KubectlFlavor.k3s => const ['/etc/rancher/k3s/k3s.yaml'],
  KubectlFlavor.kubectl => const [
    '/etc/kubernetes/admin.conf',
    '/etc/rancher/rke2/rke2.yaml',
  ],
  _ => const [],
};

const k8sReaderMarker = 'KELOLA_K8S_READER=';
const k8sReaderViaMarker = 'KELOLA_K8S_READER_VIA=';
const k8sReaderExpMarker = 'KELOLA_K8S_READER_EXP=';
const k8sReaderStepMarker = 'KELOLA_K8S_READER_STEP=';

/// The comment line in [kelolaReaderKubeconfigPath] that records the expiry.
const k8sReaderExpiresComment = '# kelola-expires: ';

String _binary(KubectlFlavor flavor) =>
    flavor == KubectlFlavor.k3s ? 'k3s' : 'kubectl';

String _sub(KubectlFlavor flavor) =>
    flavor == KubectlFlavor.k3s ? ' kubectl' : '';

/// Shared head: reads the password, resolves the CLI, picks the admin
/// credentials. Ends with `admin` defined, or after printing why not.
String _scriptHead(KubectlFlavor flavor) {
  final admins = kelolaReaderAdminConfigs(flavor).join(' ');
  final sub = _sub(flavor);
  return '''
set -u
IFS= read -r SUDO_PASS || true
umask 077
TOKOUT=''
TOKEN=''
RCACHE=''
WORK=\$(mktemp -d) || exit 1
asroot() { printf '%s\\n' "\$SUDO_PASS" | sudo -S -p '' "\$@"; }
cleanup() {
  if [ -n "\$RCACHE" ]; then asroot rm -rf -- "\$RCACHE" >/dev/null 2>&1; fi
  rm -rf -- "\$WORK"
  unset SUDO_PASS TOKOUT TOKEN
}
trap cleanup EXIT
say() { printf '%s\\n' "$k8sReaderMarker\$1"; }
fail() { say failed; printf '%s\\n' "$k8sReaderStepMarker\$1"; exit 0; }
rootowned() {
  [ -n "\$1" ] && [ -f "\$1" ] && [ ! -w "\$1" ] &&
    [ "\$(stat -c %u -- "\$1" 2>/dev/null)" = 0 ] &&
    [ "\$(stat -c %u -- "\$(dirname -- "\$1")" 2>/dev/null)" = 0 ]
}
CLI_BIN=\$(command -v ${_binary(flavor)} 2>/dev/null || true)
if ! rootowned "\$CLI_BIN"; then say nocli; exit 0; fi
cli() { "\$CLI_BIN"$sub "\$@"; }
VIA=''
ADMINCFG=''
if asroot true >/dev/null 2>&1; then
  for f in $admins; do
    if asroot test -f "\$f" >/dev/null 2>&1; then ADMINCFG=\$f; VIA=\$f; break; fi
  done
fi
if [ -n "\$ADMINCFG" ]; then
  RCACHE=\$(asroot mktemp -d 2>/dev/null) || RCACHE=''
  CACHEARG=--request-timeout=20s
  if [ -n "\$RCACHE" ]; then CACHEARG="--cache-dir=\$RCACHE"; fi
  admin() { asroot "\$CLI_BIN"$sub --kubeconfig="\$ADMINCFG" "\$CACHEARG" --request-timeout=20s "\$@"; }
elif cli auth can-i create clusterroles.rbac.authorization.k8s.io >/dev/null 2>&1 &&
  cli auth can-i create clusterrolebindings.rbac.authorization.k8s.io >/dev/null 2>&1 &&
  cli auth can-i create serviceaccounts --subresource=token --namespace=$kelolaReaderNamespace >/dev/null 2>&1; then
  VIA=own
  admin() { cli --request-timeout=20s "\$@"; }
else
  say noadmin
  exit 0
fi
admin get --raw=/version >/dev/null 2>&1 || { say unreachable; exit 0; }
''';
}

const _selector =
    'app.kubernetes.io/name=$kelolaReaderName,'
    'app.kubernetes.io/managed-by=kelola';

/// Remote sh that sets up the reader. The sudo password arrives on stdin
/// (one line) and is never in argv. The token is held in shell variables,
/// written by `printf` (a builtin, so never in argv either) into
/// [kelolaReaderKubeconfigPath] with mode 0600, and never printed.
///
/// Prints [k8sReaderMarker] with `ok`, or why not: `nocli`, `noadmin`,
/// `unreachable`, `conflict` (an object with Kelola's name that Kelola did
/// not make), `noca` (the admin kubeconfig names no CA: never written
/// without one) or `failed` with [k8sReaderStepMarker].
String buildK8sReaderSetupScript(KubectlFlavor flavor) {
  if (!kelolaReaderSupported(flavor)) {
    throw ArgumentError.value(flavor, 'flavor', 'no reader for this CLI');
  }
  final manifest = base64Encode(utf8.encode(kelolaReaderManifest()));
  const managed = r'{.metadata.labels.app\.kubernetes\.io/managed-by}';
  return '''
${_scriptHead(flavor)}for obj in namespace/$kelolaReaderNamespace clusterrole/$kelolaReaderName clusterrolebinding/$kelolaReaderName; do
  owner=\$(admin get "\$obj" --ignore-not-found --output=jsonpath='{.metadata.name}/$managed' 2>/dev/null) || fail check
  case "\$owner" in ''|*/kelola) ;; *) say conflict; exit 0 ;; esac
done
printf '%s' '$manifest' | base64 -d > "\$WORK/reader.yaml" || fail apply
admin apply --filename="\$WORK/reader.yaml" >/dev/null || fail apply
nl='
'
TOKOUT=\$(admin create token $kelolaReaderName --namespace=$kelolaReaderNamespace --duration=$kelolaReaderTokenDuration --output=jsonpath='{.status.expirationTimestamp}{"\\n"}{.status.token}' 2>/dev/null) || TOKOUT=''
case "\$TOKOUT" in
  *"\$nl"*) EXP=\${TOKOUT%%"\$nl"*}; TOKEN=\${TOKOUT#*"\$nl"} ;;
  *) EXP=''; TOKEN=\$(admin create token $kelolaReaderName --namespace=$kelolaReaderNamespace --duration=$kelolaReaderTokenDuration 2>/dev/null) || TOKEN='' ;;
esac
TOKOUT=''
case "\$TOKEN" in ''|*[!A-Za-z0-9._-]*) fail token ;; esac
case "\$EXP" in *[!0-9TZ:.+-]*) EXP='' ;; esac
SERVER=\$(admin config view --raw --minify --flatten --output=jsonpath='{.clusters[0].cluster.server}' 2>/dev/null) || SERVER=''
CA=\$(admin config view --raw --minify --flatten --output=jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null) || CA=''
case "\$SERVER" in https://?*) ;; *) fail server ;; esac
case "\$SERVER" in *[!]A-Za-z0-9._:/%[-]*) fail server ;; esac
case "\$CA" in ''|*[!A-Za-z0-9+/=]*) say noca; exit 0 ;; esac
[ -d "\$HOME/.kube" ] || mkdir -m 700 -- "\$HOME/.kube" || fail write
CFG="\$HOME/.kube/kelola.yaml"
NEW="\$HOME/.kube/.kelola.yaml.\$\$"
{
  printf '%s\\n' '# Kelola read-only ServiceAccount $kelolaReaderNamespace/$kelolaReaderName. Managed by Kelola.'
  printf '$k8sReaderExpiresComment%s\\n' "\$EXP"
  printf '%s\\n' 'apiVersion: v1' 'kind: Config' 'clusters:' '- name: kelola' '  cluster:'
  printf '    server: "%s"\\n' "\$SERVER"
  printf '    certificate-authority-data: %s\\n' "\$CA"
  printf '%s\\n' 'users:' '- name: $kelolaReaderName' '  user:'
  printf '    token: %s\\n' "\$TOKEN"
  printf '%s\\n' 'contexts:' '- name: $kelolaReaderName' '  context:' '    cluster: kelola' '    user: $kelolaReaderName' 'current-context: $kelolaReaderName'
} > "\$NEW" || { rm -f -- "\$NEW"; fail write; }
TOKEN=''
chmod 600 -- "\$NEW" && mv -f -- "\$NEW" "\$CFG" || { rm -f -- "\$NEW"; fail write; }
[ "\$(cli --kubeconfig="\$CFG" auth can-i list pods --all-namespaces 2>/dev/null)" = yes ] || fail verify
[ "\$(cli --kubeconfig="\$CFG" auth can-i get secrets --all-namespaces 2>/dev/null)" = no ] || fail verify
say ok
printf '%s\\n' "$k8sReaderViaMarker\$VIA" "$k8sReaderExpMarker\$EXP"
''';
}

/// Remote sh that removes the reader: the ClusterRoleBinding, ClusterRole
/// and Namespace (which takes the ServiceAccount, and so every token, with
/// it), selected by [kelolaReaderLabels] only, then the kubeconfig. Same
/// password handling and admin credentials as [buildK8sReaderSetupScript].
/// Prints [k8sReaderMarker] `removed`, or why not.
String buildK8sReaderRemoveScript(KubectlFlavor flavor) {
  if (!kelolaReaderSupported(flavor)) {
    throw ArgumentError.value(flavor, 'flavor', 'no reader for this CLI');
  }
  return '''
${_scriptHead(flavor)}admin delete clusterrolebinding,clusterrole,namespace --selector=$_selector --wait=false >/dev/null || fail delete
rm -f -- "\$HOME/.kube/kelola.yaml" || fail write
say removed
printf '%s\\n' "$k8sReaderViaMarker\$VIA"
''';
}

/// How a setup or removal ended.
enum K8sReaderOutcome {
  ok,
  removed,
  noCli,
  noAdmin,
  unreachable,
  conflict,
  noCa,
  failed,

  /// No marker at all: the script did not run to a decision.
  unknown,
}

class K8sReaderResult {
  const K8sReaderResult({
    required this.outcome,
    this.via = '',
    this.expires,
    this.step = '',
  });

  final K8sReaderOutcome outcome;

  /// The admin kubeconfig used, or `own` for the login's own kubeconfig.
  final String via;

  /// When the token expires, as the API server granted it.
  final DateTime? expires;

  /// The step that failed, for [K8sReaderOutcome.failed].
  final String step;
}

/// Reads the markers of [buildK8sReaderSetupScript] and
/// [buildK8sReaderRemoveScript]. Never throws.
K8sReaderResult parseK8sReaderOutput(String stdout) {
  String? value(String marker) {
    for (final line in stdout.split('\n')) {
      final l = line.trim();
      if (l.startsWith(marker)) return l.substring(marker.length);
    }
    return null;
  }

  final outcome = switch (value(k8sReaderMarker)) {
    'ok' => K8sReaderOutcome.ok,
    'removed' => K8sReaderOutcome.removed,
    'nocli' => K8sReaderOutcome.noCli,
    'noadmin' => K8sReaderOutcome.noAdmin,
    'unreachable' => K8sReaderOutcome.unreachable,
    'conflict' => K8sReaderOutcome.conflict,
    'noca' => K8sReaderOutcome.noCa,
    'failed' => K8sReaderOutcome.failed,
    _ => K8sReaderOutcome.unknown,
  };
  final exp = value(k8sReaderExpMarker) ?? '';
  return K8sReaderResult(
    outcome: outcome,
    via: value(k8sReaderViaMarker) ?? '',
    expires: exp.isEmpty ? null : DateTime.tryParse(exp)?.toUtc(),
    step: value(k8sReaderStepMarker) ?? '',
  );
}

/// Whether the login has a reader kubeconfig, and until when.
class K8sReaderStatus {
  const K8sReaderStatus({
    required this.present,
    this.expires,
    this.roleCurrent,
  });

  final bool present;
  final DateTime? expires;

  /// Whether the role still grants the newest rule Kelola added. Null when
  /// it could not be told (an expired token, an unreachable API, no CLI).
  final bool? roleCurrent;

  bool expiredAt(DateTime now) => expires != null && !expires!.isAfter(now);

  /// A reader set up before the newest rule: Renew re-applies the role.
  bool get roleOutdated => present && roleCurrent == false;
}

const k8sReaderPresentMarker = 'KELOLA_K8S_READER_PRESENT';
const k8sReaderAbsentMarker = 'KELOLA_K8S_READER_ABSENT';
const k8sReaderRoleMarker = 'KELOLA_K8S_READER_ROLE=';

/// Host details' and the Kubernetes home's copy for an old reader role.
const kelolaReaderRoleOutdatedCopy =
    'The read-only $kelolaReaderName role is outdated. '
    'Re-run Enable Kelola sudo.';

/// Never prints the token: only the expiry comment line.
const k8sReaderStatusCommand =
    'if [ -r $kelolaReaderKubeconfig ]; then '
    "sed -n 's/^$k8sReaderExpiresComment//p' $kelolaReaderKubeconfig | head -n 1; "
    'echo $k8sReaderPresentMarker; '
    'else echo $k8sReaderAbsentMarker; fi';

/// The newest rule Kelola added to [kelolaReaderRules], as a line of
/// `can-i --list`. Move it to the newest rule whenever [kelolaReaderRules]
/// grows.
const _roleProbeResource = 'applications.argoproj.io';

/// [_roleProbeResource] as a grep pattern for the start of a rule line.
final _roleProbePattern = '^${_roleProbeResource.replaceAll('.', r'\.')} ';

/// [k8sReaderStatusCommand], plus, for a host with a reader CLI, whether the
/// role still grants [_roleProbeResource].
///
/// It reads the role's own rules (`auth can-i --list`), not a `can-i` check
/// on the resource: that check goes through API discovery, and on a cluster
/// without the Argo CD CRD kubectl cannot resolve the resource, asks with an
/// empty group and gets a `no`, so every reader there would read as outdated
/// and Renew could not clear it. The rule listing does not depend on which
/// CRDs are installed.
///
/// Only a clear answer counts: `yes` when a rule line names the resource,
/// `no` only when the listing came back (its header line) without one and
/// the API answers. An expired token or a transient error prints nothing and
/// never reads as outdated. Never prints the token.
String k8sReaderStatusCommandFor(HostFacts facts) {
  final reader = kubectlReaderCli(facts);
  if (reader == null) return k8sReaderStatusCommand;
  return 'if [ -r $kelolaReaderKubeconfig ]; then '
      "sed -n 's/^$k8sReaderExpiresComment//p' $kelolaReaderKubeconfig | head -n 1; "
      'echo $k8sReaderPresentMarker; '
      'r=\$($reader auth can-i --list --request-timeout=5s 2>/dev/null); '
      "if printf '%s\\n' \"\$r\" | grep -q '$_roleProbePattern'; "
      'then echo ${k8sReaderRoleMarker}yes; '
      "elif printf '%s\\n' \"\$r\" | grep -q '^Resources ' && "
      '$reader get --raw=/version --request-timeout=5s >/dev/null 2>&1; '
      'then echo ${k8sReaderRoleMarker}no; fi; '
      'else echo $k8sReaderAbsentMarker; fi';
}

K8sReaderStatus parseK8sReaderStatus(String stdout) {
  if (!stdout.contains(k8sReaderPresentMarker)) {
    return const K8sReaderStatus(present: false);
  }
  final first = stdout.split('\n').first.trim();
  bool? roleCurrent;
  for (final line in stdout.split('\n')) {
    final l = line.trim();
    if (l.startsWith(k8sReaderRoleMarker)) {
      final v = l.substring(k8sReaderRoleMarker.length);
      roleCurrent = v == 'yes'
          ? true
          : v == 'no'
          ? false
          : null;
    }
  }
  return K8sReaderStatus(
    present: true,
    expires: first.isEmpty ||
            first == k8sReaderPresentMarker ||
            first.startsWith(k8sReaderRoleMarker)
        ? null
        : DateTime.tryParse(first)?.toUtc(),
    roleCurrent: roleCurrent,
  );
}

/// `20 Feb 2027`, in UTC, for the token expiry.
String k8sReaderDateLabel(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final u = t.toUtc();
  return '${u.day} ${months[u.month - 1]} ${u.year}';
}
