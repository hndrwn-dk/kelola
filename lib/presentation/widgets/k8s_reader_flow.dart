import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/k8s_reader.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/probes/k8s_reader_probes.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/enable_kelola_sudo_flow.dart';

/// M52e: shown in the Enable Kelola sudo preview on a host with a
/// Kubernetes CLI.
String? k8sReaderPreviewNote(KubectlFlavor flavor) {
  if (flavor == KubectlFlavor.none) {
    return null;
  }
  if (!kelolaReaderSupported(flavor)) {
    return 'Kubernetes reads use your own oc login. Kelola creates no '
        'account for oc.';
  }
  return 'Kubernetes reads move to a read-only $kelolaReaderName account, '
      'applied with the cluster\'s admin credentials and your sudo '
      'password: get and list on the objects below, never Secrets, '
      'ConfigMaps, exec, attach or port-forward. Kelola asks it for named '
      'columns only. Describe, YAML, rollout history and every change keep '
      'using your own kubeconfig. The role can read pod specs, so keep '
      'credentials in Secrets, not in env values.';
}

/// M52e: the objects and token step, for the preview's mono box.
List<String> k8sReaderPreviewLines() => [
  '# Kubernetes: kubectl apply (read-only account)',
  for (final o in kelolaReaderObjectLines) ...[
    o,
    if (o.startsWith('ClusterRole '))
      for (final r in kelolaReaderRuleLines()) '  $r',
  ],
  '# token: kubectl create token, $kelolaReaderTokenDays days',
  '# -> $kelolaReaderKubeconfigPath (mode 0600)',
];

const _keepsOwn = ' Kubernetes reads keep using your own kubeconfig.';

/// What a setup or removal [r] means, for the result sheet.
List<GrantNote> k8sReaderNotes(K8sReaderResult r) {
  const lead = 'Kubernetes reader not set up: ';
  final until = r.expires == null
      ? ''
      : ' Token until ${k8sReaderDateLabel(r.expires!)}.';
  return switch (r.outcome) {
    K8sReaderOutcome.ok => [
      (
        lead:
            'Kubernetes reads now use the read-only $kelolaReaderName '
            'account, from ',
        path: kelolaReaderKubeconfigPath,
        tail: '.$until',
      ),
    ],
    K8sReaderOutcome.removed => [
      (
        lead: 'Removed the $kelolaReaderName account and ',
        path: kelolaReaderKubeconfigPath,
        tail: '.$_keepsOwn',
      ),
    ],
    K8sReaderOutcome.noCli => [
      (
        lead:
            '${lead}the Kubernetes CLI is not a root-owned file in a '
            'system directory.',
        path: '',
        tail: _keepsOwn,
      ),
    ],
    K8sReaderOutcome.noAdmin => [
      (
        lead:
            '${lead}no admin kubeconfig found and your own cannot create '
            'cluster roles.',
        path: '',
        tail: _keepsOwn,
      ),
    ],
    K8sReaderOutcome.unreachable => [
      (
        lead: '${lead}the cluster API did not answer.',
        path: '',
        tail: _keepsOwn,
      ),
    ],
    K8sReaderOutcome.conflict => [
      (
        lead:
            '${lead}the $kelolaReaderNamespace namespace or a '
            '$kelolaReaderName role already exists and Kelola did not create '
            'it.',
        path: '',
        tail: _keepsOwn,
      ),
    ],
    K8sReaderOutcome.noCa => [
      (
        lead:
            '${lead}the admin kubeconfig names no CA certificate, and '
            'Kelola writes no kubeconfig without one.',
        path: '',
        tail: _keepsOwn,
      ),
    ],
    K8sReaderOutcome.failed => [
      (
        lead: '${lead}the ${r.step.isEmpty ? 'setup' : r.step} step failed.',
        path: '',
        tail: _keepsOwn,
      ),
    ],
    K8sReaderOutcome.unknown => [
      (lead: '${lead}the setup did not finish.', path: '', tail: _keepsOwn),
    ],
  };
}

/// Runs [K8sReaderSetupProbe] with the password the user already gave.
/// Never throws: a failure is a note, and never undoes the sudoers file.
Future<List<GrantNote>> runK8sReaderSetup({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  required HostFacts facts,
  required String? Function() password,
}) async {
  final pass = password();
  if (pass == null || pass.isEmpty || !context.mounted) {
    return const [];
  }
  try {
    final r = await runHostProbe(
      ref: ref,
      context: context,
      host: host,
      facts: facts,
      probe: const K8sReaderSetupProbe(),
      stdinBytes: utf8.encode('$pass\n'),
    );
    return k8sReaderNotes(r);
  } catch (_) {
    return k8sReaderNotes(
      const K8sReaderResult(outcome: K8sReaderOutcome.unknown),
    );
  }
}

const k8sReaderRemoveTitle = 'Remove the Kubernetes reader?';

const k8sReaderRemoveBody =
    'Deletes the ClusterRoleBinding and ClusterRole $kelolaReaderName and '
    'the $kelolaReaderNamespace namespace with its ServiceAccount, which '
    'ends every token issued for it, then $kelolaReaderKubeconfigPath. Only '
    'objects labelled as Kelola\'s are deleted. Kubernetes reads go back to '
    'your own kubeconfig.';

/// Confirms, asks for the sudo password once, and removes the reader.
/// Returns true when the host says it was removed.
Future<bool> runK8sReaderRemoveFlow({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  required HostFacts facts,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => KelolaSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
        child: RiskBand(
          risk: RiskLevel.mutate,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                k8sReaderRemoveTitle,
                style: KelolaType.display(color: ctx.kc.text, size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                k8sReaderRemoveBody,
                style: KelolaType.body(color: ctx.kc.muted, size: 13),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Remove'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) {
    return false;
  }
  final password = EphemeralPassword();
  final lifecycle = SudoPasswordLifecycle(password);
  WidgetsBinding.instance.addObserver(lifecycle);
  try {
    final entered = await showPasswordEntrySheet(
      context,
      password: password,
      title: 'Sudo password',
      body:
          'Enter your sudo password for this host. Kelola uses it once and '
          'does not store it.',
    );
    final pass = password.read();
    if (!entered || pass == null || pass.isEmpty || !context.mounted) {
      return false;
    }
    K8sReaderResult result;
    try {
      result = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        facts: facts,
        probe: const K8sReaderRemoveProbe(),
        stdinBytes: utf8.encode('$pass\n'),
      );
    } catch (_) {
      result = const K8sReaderResult(outcome: K8sReaderOutcome.unknown);
    } finally {
      password.clear();
    }
    if (context.mounted) {
      final note = result.outcome == K8sReaderOutcome.removed
          ? 'Kubernetes reader removed'
          : 'Kubernetes reader not removed: '
                '${_removeFailure(result)}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    }
    return result.outcome == K8sReaderOutcome.removed;
  } finally {
    WidgetsBinding.instance.removeObserver(lifecycle);
    password.clear();
  }
}

String _removeFailure(K8sReaderResult r) => switch (r.outcome) {
  K8sReaderOutcome.noCli => 'no root-owned Kubernetes CLI',
  K8sReaderOutcome.noAdmin => 'no admin credentials',
  K8sReaderOutcome.unreachable => 'the cluster API did not answer',
  K8sReaderOutcome.failed => 'the ${r.step} step failed',
  _ => 'it did not finish',
};

/// The Kubernetes home's Read access copy for [status] at [now].
String k8sReaderStatusLine(K8sReaderStatus status, DateTime now) {
  if (!status.present) {
    return 'Reads use your own kubeconfig. Enable Kelola sudo can set up a '
        'read-only $kelolaReaderName account with your sudo password.';
  }
  final exp = status.expires;
  if (exp != null && status.expiredAt(now)) {
    return 'The $kelolaReaderName token expired on '
        '${k8sReaderDateLabel(exp)}. Reads use your own kubeconfig until you '
        'renew it.';
  }
  if (status.roleOutdated) return kelolaReaderRoleOutdatedCopy;
  if (exp == null) {
    return 'Reads use the read-only $kelolaReaderName account.';
  }
  return 'Reads use the read-only $kelolaReaderName account. Token until '
      '${k8sReaderDateLabel(exp)}.';
}

/// M52e: the Kubernetes home's Read access block. [onSetUp] runs Enable
/// Kelola sudo (which also renews); [onRemove] runs the remove flow.
class K8sReaderAccessBlock extends StatelessWidget {
  const K8sReaderAccessBlock({
    super.key,
    required this.status,
    required this.now,
    required this.onSetUp,
    required this.onRemove,
  });

  final K8sReaderStatus status;
  final DateTime now;
  final VoidCallback? onSetUp;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return RiskBand(
      risk: RiskLevel.read,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            k8sReaderStatusLine(status, now),
            style: KelolaType.body(color: c.muted, size: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onSetUp,
                  child: Text(status.present ? 'Renew' : 'Set up'),
                ),
              ),
              if (status.present) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRemove,
                    child: const Text('Remove'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
