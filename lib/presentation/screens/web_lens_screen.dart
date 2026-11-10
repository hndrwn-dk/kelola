import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';

/// M52 §5d: the web lens (nginx / Apache httpd). Stub until Task 8 adds
/// the body.
class WebLensScreen extends ConsumerStatefulWidget {
  const WebLensScreen({super.key, required this.hostId, required this.service});

  final String hostId;
  final DetectedService service;

  @override
  ConsumerState<WebLensScreen> createState() => _WebLensScreenState();
}

class _WebLensScreenState extends ConsumerState<WebLensScreen> {
  @override
  Widget build(BuildContext context) {
    final label = descriptorFor(widget.service.id).label;
    return KelolaPage(
      title: label,
      bar: KelolaHostAppBar(
        hostAlias: watchedHostAlias(ref, widget.hostId),
        title: label,
      ),
      body: const SizedBox.shrink(),
    );
  }
}
