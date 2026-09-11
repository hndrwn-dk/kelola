import 'package:kelola/domain/llm/endpoint_locality.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';

/// Outbound assist payloads need an explicit preview approve once per
/// endpoint key per app session when the destination is cloud-typed or
/// not a local endpoint.
class AssistPreviewGate {
  AssistPreviewGate();

  final Set<String> _approvedKeys = {};

  bool needsPreview(LlmSettings settings) {
    if (!_requiresPreview(settings)) {
      return false;
    }
    return !_approvedKeys.contains(endpointKey(settings));
  }

  void markApproved(LlmSettings settings) {
    if (!_requiresPreview(settings)) {
      return;
    }
    _approvedKeys.add(endpointKey(settings));
  }

  /// Stable session key: `scheme://host:port` (lowercased, default port filled).
  static String endpointKey(LlmSettings settings) {
    final uri = settings.baseUri;
    if (uri == null) {
      return 'unknown://';
    }
    final scheme = (uri.scheme.isEmpty ? 'http' : uri.scheme).toLowerCase();
    var host = uri.host.trim().toLowerCase();
    if (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    final port = uri.hasPort
        ? uri.port
        : (scheme == 'https'
            ? 443
            : scheme == 'http'
                ? 80
                : uri.port);
    return '$scheme://$host:$port';
  }

  static bool _requiresPreview(LlmSettings settings) {
    if (settings.provider == LlmProvider.openaiCompatible) {
      return true;
    }
    if (settings.provider == LlmProvider.ollama) {
      return !isLocalEndpoint(settings.baseUri);
    }
    return false;
  }
}
