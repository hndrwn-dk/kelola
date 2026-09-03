import 'package:kelola/domain/containers/container_engine.dart';
import 'package:kelola/domain/containers/container_images.dart';
import 'package:kelola/domain/containers/container_images_parser.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class ContainerImagesProbe extends Probe<ContainerImageInventory> {
  const ContainerImagesProbe({this.engine = 'docker'});

  final String engine;

  @override
  String get auditTitle => 'Listed container images';

  @override
  String command(HostFacts facts) {
    final bin = containerEngineBin(engine);
    final format = engine == 'podman' ? 'json' : r"'{{json .}}'";
    return '''
LC_ALL=C
echo "---IMAGES---"
$bin images --format $format 2>/dev/null || sudo -n $bin images --format $format
echo "---DF---"
$bin system df 2>/dev/null || sudo -n $bin system df
''';
  }

  @override
  ContainerImageInventory parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(
          kind: SudoHintKind.containerRead,
          binary: engine == 'podman' ? '/usr/bin/podman' : '/usr/bin/docker',
          verb: 'images',
        ),
      );
    }
    return const ContainerImagesParser().parse(stdout, engine: engine);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 25);
}
