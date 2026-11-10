/// M52: the closed set of services Kelola knows how to detect. M54/M55 add
/// values.
enum ServiceId { nginx, apache, mariadb, mysql, postgres }

enum ServiceFamily { web, database }

class ServiceDescriptor {
  const ServiceDescriptor({
    required this.id,
    required this.family,
    required this.label,
    required this.systemdUnits,
    required this.openrcServices,
    required this.binaries,
    required this.defaultPorts,
    this.versionCommand,
  });

  final ServiceId id;
  final ServiceFamily family;

  /// Human label, e.g. `Apache httpd`.
  final String label;

  /// systemd unit names; `*` matches any run of characters.
  final List<String> systemdUnits;
  final List<String> openrcServices;

  /// Binary names; the first one found on the host wins.
  final List<String> binaries;

  /// Display hint only: never used to attribute a listening port.
  final List<int> defaultPorts;

  /// Shell fragment that prints one line. `<bin>` stands for the binary
  /// found on the host.
  final String? versionCommand;

  /// True when [unit] is one of [systemdUnits]. Exact match, except that `*`
  /// in a catalog entry matches any run of characters (including none).
  bool matchesSystemdUnit(String unit) {
    if (unit.isEmpty) {
      return false;
    }
    for (final pattern in systemdUnits) {
      if (_globMatch(pattern, unit)) {
        return true;
      }
    }
    return false;
  }
}

bool _globMatch(String pattern, String text) {
  if (!pattern.contains('*')) {
    return pattern == text;
  }
  final re = RegExp(
    '^${pattern.split('*').map(RegExp.escape).join('.*')}\$',
    dotAll: true,
  );
  return re.hasMatch(text);
}

/// mariadb lists `mysqld.service` / `mysql.service` as aliases (Debian);
/// the probe parser disambiguates mariadb vs mysql by version string.
const List<ServiceDescriptor> kServiceCatalog = [
  ServiceDescriptor(
    id: ServiceId.nginx,
    family: ServiceFamily.web,
    label: 'nginx',
    systemdUnits: ['nginx.service'],
    openrcServices: ['nginx'],
    binaries: ['nginx'],
    defaultPorts: [80, 443],
    versionCommand: 'nginx -v 2>&1',
  ),
  ServiceDescriptor(
    id: ServiceId.apache,
    family: ServiceFamily.web,
    label: 'Apache httpd',
    systemdUnits: ['httpd.service', 'apache2.service'],
    openrcServices: ['apache2'],
    binaries: ['httpd', 'apache2', 'apachectl', 'apache2ctl'],
    defaultPorts: [80, 443],
    versionCommand: '<bin> -v 2>&1 | head -1',
  ),
  ServiceDescriptor(
    id: ServiceId.mariadb,
    family: ServiceFamily.database,
    label: 'MariaDB',
    systemdUnits: ['mariadb.service', 'mysqld.service', 'mysql.service'],
    openrcServices: ['mariadb'],
    binaries: ['mariadbd', 'mariadb'],
    defaultPorts: [3306],
    versionCommand: 'mariadb --version',
  ),
  ServiceDescriptor(
    id: ServiceId.mysql,
    family: ServiceFamily.database,
    label: 'MySQL',
    systemdUnits: ['mysqld.service', 'mysql.service'],
    openrcServices: ['mysql'],
    binaries: ['mysqld', 'mysql'],
    defaultPorts: [3306],
    versionCommand: 'mysql --version',
  ),
  ServiceDescriptor(
    id: ServiceId.postgres,
    family: ServiceFamily.database,
    label: 'PostgreSQL',
    systemdUnits: [
      'postgresql.service',
      'postgresql@*.service',
      'postgresql-*.service',
    ],
    openrcServices: ['postgresql'],
    binaries: ['postgres', 'psql', 'pg_ctl'],
    defaultPorts: [5432],
    versionCommand: 'psql --version',
  ),
];

ServiceDescriptor descriptorFor(ServiceId id) =>
    kServiceCatalog.firstWhere((d) => d.id == id);

/// M52 ships lenses for the web family only.
bool hasLens(ServiceId id) =>
    id == ServiceId.nginx || id == ServiceId.apache;
