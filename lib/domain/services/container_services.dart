import 'service_catalog.dart';
import 'service_detection.dart';

/// M52c: which catalog service a Docker container runs, from its image and
/// command as `docker ps --no-trunc` printed them. Pure; the host is
/// untrusted, so nothing here is ever used in a command except a name that
/// passes [isSafeContainerName].

/// Docker's own rule for container names, capped at 128 characters.
final _containerName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$');

/// Whether [name] may be single-quoted into a docker command and matched by
/// the Containers sudo rules.
bool isSafeContainerName(String name) => _containerName.hasMatch(name);

/// `docker.io/library/php:8.3-apache@sha256:…` -> (repo `php`, tag
/// `8.3-apache`). Registry, namespace and digest are dropped; no tag -> ''.
({String repo, String tag}) splitImage(String image) {
  var s = image.trim();
  final at = s.indexOf('@');
  if (at >= 0) s = s.substring(0, at);
  final slash = s.lastIndexOf('/');
  final last = slash >= 0 ? s.substring(slash + 1) : s;
  final colon = last.indexOf(':');
  return colon >= 0
      ? (
          repo: last.substring(0, colon).toLowerCase(),
          tag: last.substring(colon + 1).toLowerCase(),
        )
      : (repo: last.toLowerCase(), tag: '');
}

/// The catalog service [image] / [command] runs, or null. First rule wins
/// (spec §1): web servers before databases, image before command.
ServiceId? serviceIdForContainer({
  required String image,
  required String command,
}) {
  final (:repo, :tag) = splitImage(image);
  final cmd = command.toLowerCase();
  final firstWord = cmd.replaceAll('"', ' ').trim().split(RegExp(r'\s+')).first;

  if (const {'nginx', 'nginx-unprivileged', 'openresty'}.contains(repo) ||
      cmd.contains('nginx -g')) {
    return ServiceId.nginx;
  }
  if (repo == 'httpd' ||
      (repo == 'php' && tag.contains('apache')) ||
      cmd.contains('apache2-foreground') ||
      cmd.contains('httpd-foreground')) {
    return ServiceId.apache;
  }
  if (repo == 'mariadb' || cmd.contains('mariadbd')) {
    return ServiceId.mariadb;
  }
  if (const {'mysql', 'percona-server'}.contains(repo) ||
      cmd.contains('mysqld')) {
    return ServiceId.mysql;
  }
  if (const {'postgres', 'postgis'}.contains(repo) || firstWord == 'postgres') {
    return ServiceId.postgres;
  }
  return null;
}

/// The tag as a version only when it is digits and dots (`11.4`, `2.4.62`).
String? versionFromTag(String tag) =>
    RegExp(r'^\d+(\.\d+)*$').hasMatch(tag) ? tag : null;

/// Official images whose tag is the service's own version. `php:8.3-apache`
/// and `phpmyadmin:5` are not Apache versions.
const _versionedRepos = <ServiceId, Set<String>>{
  ServiceId.nginx: {'nginx', 'nginx-unprivileged'},
  ServiceId.apache: {'httpd'},
  ServiceId.mariadb: {'mariadb'},
  ServiceId.mysql: {'mysql', 'percona-server'},
  ServiceId.postgres: {'postgres'},
};

/// The service version [image]'s tag names, only for [id]'s official image.
String? containerServiceVersion(ServiceId id, String image) {
  final (:repo, :tag) = splitImage(image);
  return (_versionedRepos[id] ?? const {}).contains(repo)
      ? versionFromTag(tag)
      : null;
}

/// Docker `State` -> [ServiceState]. Unknown words read as stopped.
ServiceState containerServiceState(String state) =>
    switch (state.trim().toLowerCase()) {
      'running' => ServiceState.running,
      'restarting' => ServiceState.failed,
      _ => ServiceState.stopped,
    };
