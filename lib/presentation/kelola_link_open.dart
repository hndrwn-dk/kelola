import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/deep_link.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';

Future<HostDashboardScreen?> dashboardForLink(
  HostRepository repo,
  KelolaLink link,
) async {
  final id = link.hostId;
  if (id == null || id.isEmpty) {
    return null;
  }
  final host = await repo.get(id);
  if (host == null) {
    return null;
  }
  return HostDashboardScreen(
    hostId: id,
    openIncident: link.incident,
    openTunnels: link.tunnel,
    openUnitName: link.unitName,
  );
}
