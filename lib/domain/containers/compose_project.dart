import 'package:kelola/domain/containers/container_row.dart';

String composeWorkingDir(Map<String, String> labels) {
  return labels['com.docker.compose.project.working_dir'] ??
      labels['io.podman.compose.project.working_dir'] ??
      '';
}

bool composeProjectReady(ContainerRow row) {
  return row.composeProject.trim().isNotEmpty &&
      composeWorkingDir(row.labels).isNotEmpty;
}

String? composeWorkingDirForProject(Iterable<ContainerRow> rows, String project) {
  for (final row in rows) {
    if (row.composeProject != project) {
      continue;
    }
    final dir = composeWorkingDir(row.labels);
    if (dir.isNotEmpty) {
      return dir;
    }
  }
  return null;
}
