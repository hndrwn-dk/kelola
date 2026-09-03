import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/firewall/firewall_auto_revert.dart';
import 'package:kelola/domain/firewall/firewall_lockout.dart';
import 'package:kelola/domain/firewall/firewall_parser.dart';
import 'package:kelola/domain/firewall/firewall_snapshot.dart';
import 'package:kelola/domain/probes/firewall_apply_probe.dart';
import 'package:kelola/domain/probes/firewall_list_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';

String fixture(String name) =>
    File('test/fixtures/firewall/$name').readAsStringSync();

HostFacts factsOf(FirewallBackend fw) {
  return HostFacts(
    osId: 'test',
    osVersionId: '1',
    init: InitSystem.systemd,
    systemdVersion: 255,
    pkg: PackageManager.unknown,
    fw: fw,
    hasJournald: true,
    journalReadable: true,
    arch: 'x86_64',
  );
}

void main() {
  const parser = FirewallParser();

  test('list commands come from HostFacts.fw', () {
    const probe = FirewallListProbe();
    final firewalld = probe.command(factsOf(FirewallBackend.firewalld));
    expect(firewalld, contains('echo firewalld'));
    expect(firewalld, contains('firewall-cmd --list-all'));
    expect(firewalld, isNot(contains('command -v firewall-cmd')));

    expect(
      probe.command(factsOf(FirewallBackend.ufw)),
      contains('ufw status verbose'),
    );
    expect(
      probe.command(factsOf(FirewallBackend.nftables)),
      contains('nft -j list ruleset'),
    );
    expect(
      probe.command(factsOf(FirewallBackend.iptables)),
      contains('iptables-save'),
    );
  });

  test('parses firewalld, ufw, nft JSON, iptables-save', () {
    final fd = parser.parse(
      backend: FirewallBackend.firewalld,
      stdout: fixture('firewalld_list_all.txt'),
    );
    expect(fd.rules.map((r) => r.service), contains('ssh'));
    expect(fd.rules.map((r) => r.port), contains('8080/tcp'));

    final ufw = parser.parse(
      backend: FirewallBackend.ufw,
      stdout: fixture('ufw_status.txt'),
    );
    expect(ufw.rules.map((r) => r.port), contains('22/tcp'));
    expect(ufw.defaultPolicy, contains('deny'));

    final nft = parser.parse(
      backend: FirewallBackend.nftables,
      stdout: fixture('nft_ruleset.json'),
    );
    expect(nft.rules, hasLength(2));
    expect(nft.rules.first.port, '22/tcp');
    expect(nft.rules.first.handle, '12');

    final ipt = parser.parse(
      backend: FirewallBackend.iptables,
      stdout: fixture('iptables_save.txt'),
    );
    expect(ipt.readOnly, isTrue);
    expect(ipt.rules.map((r) => r.port), contains('22/tcp'));
  });

  test('SSH-port rules trip the existing lockout idea', () {
    expect(
      firewallTouchesSsh(port: '22/tcp', sshPort: 22),
      isTrue,
    );
    expect(
      firewallTouchesSsh(port: '2222/tcp', service: 'ssh', sshPort: 22),
      isTrue,
    );
    expect(
      firewallTouchesSsh(port: '8080/tcp', sshPort: 22),
      isFalse,
    );
    expect(
      isFirewallLockoutChange(
        const FirewallChange(verb: FirewallVerb.removePort, port: '22/tcp'),
        sshPort: 22,
      ),
      isTrue,
    );
    expect(
      isFirewallLockoutChange(
        const FirewallChange(verb: FirewallVerb.addPort, port: '8080/tcp'),
        sshPort: 22,
      ),
      isFalse,
    );
  });

  test('apply is destructive; iptables mutate is refused; firewalld times out',
      () {
    const add = FirewallChange(verb: FirewallVerb.addPort, port: '8080/tcp');
    const probe = FirewallApplyProbe(add);
    expect(probe.risk, RiskLevel.destructive);
    expect(probe.auditTitle, 'Applied firewall rule');
    final firewalld = probe.command(factsOf(FirewallBackend.firewalld));
    expect(firewalld, contains('--timeout=60'));
    expect(firewalld, isNot(contains('sleep 60')));
    expect(
      probe.command(factsOf(FirewallBackend.iptables)),
      contains('read-only'),
    );
    expect(
      () => probe.parse('read-only\n', '', 1),
      throwsA(isA<Exception>()),
    );
    expect(
      const FirewallRevertProbe(add).auditTitle,
      'Reverted firewall rule',
    );
  });

  test('ufw and nft schedule host sleep revert before the mutate, never sudo sh',
      () {
    const add = FirewallChange(verb: FirewallVerb.addPort, port: '8080/tcp');
    const probe = FirewallApplyProbe(add);
    final ufw = probe.command(factsOf(FirewallBackend.ufw));
    expect(ufw, contains('sleep 60'));
    expect(ufw, contains('---REVERT_PID---'));
    expect(ufw.indexOf('sleep 60'), lessThan(ufw.indexOf('ufw allow')));
    expect(ufw, isNot(contains('sudo -n sh')));
    expect(ufw, isNot(contains('sudo -n /bin/sh')));
    expect(ufw, isNot(contains('sudo -n /usr/bin/sh')));
    expect(ufw, contains('sudo -n /usr/sbin/ufw delete allow'));

    final nft = probe.command(factsOf(FirewallBackend.nftables));
    expect(nft.indexOf('sleep 60'), lessThan(nft.indexOf('nft add rule')));
    expect(nft, isNot(contains('sudo -n sh')));
    expect(nft, contains('---REVERT_PID---'));

    const remove = FirewallChange(
      verb: FirewallVerb.removePort,
      port: '8080/tcp',
    );
    final fdRm = FirewallApplyProbe(remove)
        .command(factsOf(FirewallBackend.firewalld));
    expect(fdRm.indexOf('sleep 60'), lessThan(fdRm.indexOf('--remove-port')));
  });

  test('Keep cancels the host sleep by PID; sudo hint is the firewall binary',
      () {
    const change = FirewallChange(
      verb: FirewallVerb.addPort,
      port: '8080/tcp',
      revertPid: 4242,
    );
    final keep = FirewallKeepProbe(change)
        .command(factsOf(FirewallBackend.ufw));
    expect(keep, contains('kill 4242'));
    expect(keep, isNot(contains('sudo -n sh')));
    expect(
      kelolaSudoHint(
        user: 'hendra',
        context: const SudoHintContext(
          kind: SudoHintKind.firewall,
          binary: '/usr/sbin/ufw allow 8080/tcp',
        ),
      ).snippet,
      contains('NOPASSWD: /usr/sbin/ufw allow 8080/tcp'),
    );
    expect(
      kelolaSudoHint(
        user: 'hendra',
        context: const SudoHintContext(
          kind: SudoHintKind.firewall,
          binary: '/usr/sbin/ufw allow 8080/tcp',
        ),
      ).snippet,
      isNot(contains('/bin/sh')),
    );
  });

  test('unconfirmed window expires without an app-side mutate', () {
    fakeAsync((async) {
      final log = <String>[];
      final ctrl = FirewallAutoRevert(
        apply: () async {
          log.add('apply');
        },
        onExpired: () async {
          log.add('expired');
        },
      );
      final future = ctrl.start();
      async.flushMicrotasks();
      expect(log, ['apply']);
      expect(ctrl.expired, isFalse);
      async.elapse(const Duration(seconds: 59));
      async.flushMicrotasks();
      expect(log, ['apply']);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(log, ['apply', 'expired']);
      expect(ctrl.expired, isTrue);
      expect(ctrl.confirmed, isFalse);
      future.then((kept) => expect(kept, isFalse));
      async.flushMicrotasks();
    });
  });

  test('Keep cancels the UI window; host rollback is the sleep PID', () {
    fakeAsync((async) {
      final log = <String>[];
      final ctrl = FirewallAutoRevert(
        apply: () async {
          log.add('apply');
        },
        onExpired: () async {
          log.add('expired');
        },
      );
      ctrl.start();
      async.flushMicrotasks();
      ctrl.confirm();
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(log, ['apply']);
      expect(ctrl.expired, isFalse);
      expect(ctrl.confirmed, isTrue);
    });
  });
}
