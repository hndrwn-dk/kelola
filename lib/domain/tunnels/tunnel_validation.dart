import 'package:kelola/domain/tunnels/tunnel_target.dart';

class TunnelValidationResult {
  const TunnelValidationResult.ok() : error = null;
  const TunnelValidationResult.invalid(this.error);

  final String? error;
  bool get isOk => error == null;
}

TunnelValidationResult validateTunnelTarget(TunnelTarget target) {
  final label = target.label.trim();
  if (label.isEmpty) {
    return const TunnelValidationResult.invalid('Label is required');
  }
  if (label.length > 40) {
    return const TunnelValidationResult.invalid('Label must be at most 40 characters');
  }

  if (target.remotePort < 1 || target.remotePort > 65535) {
    return const TunnelValidationResult.invalid(
      'Remote port must be between 1 and 65535',
    );
  }

  final host = target.remoteHost.trim();
  if (host.isEmpty) {
    return const TunnelValidationResult.invalid('Remote host is required');
  }
  if (host == '0.0.0.0') {
    return const TunnelValidationResult.invalid('Remote host cannot be 0.0.0.0');
  }
  if (host.contains(RegExp(r'\s'))) {
    return const TunnelValidationResult.invalid('Remote host must not contain spaces');
  }
  if (host.contains('://')) {
    return const TunnelValidationResult.invalid('Remote host must not include a scheme');
  }
  if (host.contains('/')) {
    return const TunnelValidationResult.invalid('Remote host must not include a path');
  }
  if (_hasPortSuffix(host)) {
    return const TunnelValidationResult.invalid('Remote host must not include a port');
  }

  final path = target.path;
  if (path.isNotEmpty && !path.startsWith('/')) {
    return const TunnelValidationResult.invalid('Path must be empty or start with /');
  }

  return const TunnelValidationResult.ok();
}

bool _hasPortSuffix(String host) {
  if (host.startsWith('[')) {
    final end = host.indexOf(']');
    if (end == -1) {
      return false;
    }
    final suffix = host.substring(end + 1);
    return suffix.startsWith(':') && int.tryParse(suffix.substring(1)) != null;
  }

  final colonCount = ':'.allMatches(host).length;
  if (colonCount != 1) {
    return false;
  }

  final portPart = host.split(':').last;
  return int.tryParse(portPart) != null;
}
