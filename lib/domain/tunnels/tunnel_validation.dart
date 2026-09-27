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

  switch (target.kind) {
    case TunnelKind.dynamic:
      return const TunnelValidationResult.ok();
    case TunnelKind.kubectl:
      return _validateKubectl(target);
    case TunnelKind.remote:
      return _validateHostAndPort(target, checkPath: false);
    case TunnelKind.local:
      return _validateHostAndPort(target, checkPath: true);
  }
}

TunnelValidationResult _validateKubectl(TunnelTarget target) {
  if (target.remotePort < 1 || target.remotePort > 65535) {
    return const TunnelValidationResult.invalid(
      'Remote port must be between 1 and 65535',
    );
  }

  final resource = target.remoteHost.trim();
  if (resource.isEmpty) {
    return const TunnelValidationResult.invalid('Resource is required');
  }
  if (resource.contains(RegExp(r'\s'))) {
    return const TunnelValidationResult.invalid('Resource must not contain spaces');
  }
  if (resource.contains('://')) {
    return const TunnelValidationResult.invalid('Resource must not include a scheme');
  }
  if (!RegExp(r'^[A-Za-z0-9][-A-Za-z0-9.]*/[A-Za-z0-9][-A-Za-z0-9.]*$')
      .hasMatch(resource)) {
    return const TunnelValidationResult.invalid('Resource must be kind/name');
  }

  final ns = target.path.trim();
  if (ns.startsWith('/')) {
    return const TunnelValidationResult.invalid('Namespace must not start with /');
  }
  if (ns.contains(RegExp(r'\s'))) {
    return const TunnelValidationResult.invalid('Namespace must not contain spaces');
  }
  if (ns.contains('/')) {
    return const TunnelValidationResult.invalid('Namespace must not include a path');
  }

  return const TunnelValidationResult.ok();
}

TunnelValidationResult _validateHostAndPort(
  TunnelTarget target, {
  required bool checkPath,
}) {
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

  if (checkPath) {
    final path = target.path;
    if (path.isNotEmpty && !path.startsWith('/')) {
      return const TunnelValidationResult.invalid('Path must be empty or start with /');
    }
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
