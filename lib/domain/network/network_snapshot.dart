class NetInterface {
  const NetInterface({
    required this.name,
    required this.operstate,
    this.addresses = const [],
  });

  final String name;
  final String operstate;
  final List<String> addresses;

  bool get isUp => operstate.toUpperCase() == 'UP';
}

class NetRoute {
  const NetRoute({
    required this.dst,
    this.gateway,
    this.dev,
    this.metric,
  });

  final String dst;
  final String? gateway;
  final String? dev;
  final int? metric;

  String get meta {
    final parts = <String>[];
    if (gateway != null && gateway!.isNotEmpty) {
      parts.add('via $gateway');
    }
    if (dev != null && dev!.isNotEmpty) {
      parts.add('dev $dev');
    }
    if (metric != null) {
      parts.add('metric $metric');
    }
    return parts.join(' ');
  }
}

class ListenPort {
  const ListenPort({
    required this.proto,
    required this.local,
    this.process = '',
    this.pid,
    this.state = 'LISTEN',
  });

  final String proto;
  final String local;
  final String process;
  final int? pid;
  final String state;
}

class NetworkSnapshot {
  const NetworkSnapshot({
    this.interfaces = const [],
    this.routes = const [],
    this.ports = const [],
  });

  final List<NetInterface> interfaces;
  final List<NetRoute> routes;
  final List<ListenPort> ports;
}
