enum OsIconKind { ubuntu, debian, fedora, alpine, arch, rhel, linux }

OsIconKind osIconKind(String? osId) {
  final id = (osId ?? '').trim().toLowerCase();
  return switch (id) {
    'ubuntu' || 'ubuntu-core' => OsIconKind.ubuntu,
    'debian' => OsIconKind.debian,
    'fedora' => OsIconKind.fedora,
    'alpine' => OsIconKind.alpine,
    'arch' || 'archlinux' || 'manjaro' => OsIconKind.arch,
    'rhel' ||
    'centos' ||
    'rocky' ||
    'almalinux' ||
    'ol' ||
    'oracle' =>
      OsIconKind.rhel,
    _ => OsIconKind.linux,
  };
}
