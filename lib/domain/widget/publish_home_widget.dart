import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';

/// Writes the last refresh snapshot to the OS widget. Never opens SSH.
Future<void> publishHomeWidget({
  required HostRepository repo,
  required HomeWidgetBridge bridge,
}) async {
  final enabled = await repo.widgetEnabled();
  final hosts = await repo.list();
  final snap = pickWorstHostSnapshot(hosts, enabled: enabled);
  await bridge.write(snap);
}
