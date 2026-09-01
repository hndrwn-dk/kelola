enum InitSystem { systemd, openrc, sysvinit, unknown }

enum PackageManager { apt, dnf, yum, zypper, apk, pacman, unknown }

enum FirewallBackend { firewalld, ufw, nftables, iptables, none }

enum HostAttention { failedUnits, diskHigh, unreachable, healthy, unknown }

enum KeyBackend { strongbox, secureEnclave, tee, software, unknown }
