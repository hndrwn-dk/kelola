import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';

void main() {
  test('host facts probe is one batched script with DMI ADDR GPU sentinels',
      () {
    const script = HostFactsProbe.script;
    expect(script, contains('---OS---'));
    expect(script, contains('---NPROC---'));
    expect(script, contains('---DMI---'));
    expect(script, contains('---VIRT---'));
    expect(script, isNot(contains('---SERIAL---')));
    expect(script, contains('---ADDR---'));
    expect(script, contains('---GPU---'));
    expect(script, contains('---NVIDIA---'));
    expect(script, contains('/sys/devices/virtual/dmi/id'));
    expect(script, contains('product_serial'));
    expect(script, isNot(contains('dmidecode')));
    expect(script, isNot(contains('sudo -n')));
    expect(script, contains('ip -j addr'));
    expect(script, contains("grep -Ei 'vga|3d|display'"));
    expect(script, contains('nvidia-smi'));
    expect(script, contains('systemd-detect-virt'));
    expect(const HostFactsProbe().needsSudo, isFalse);
    expect(const HostFactsProbe().command(HostFacts.undiscovered), script);
  });
}
