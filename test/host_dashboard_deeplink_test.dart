import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/units_screen.dart';

void main() {
  test('destination priority is tunnel, unit, incident', () {
    expect(
      dashboardDeepLinkDestination(
        openTunnels: true,
        openUnitName: 'nginx.service',
        openIncident: true,
      ),
      DeepLinkDestination.tunnels,
    );
    expect(
      dashboardDeepLinkDestination(
        openTunnels: false,
        openUnitName: 'nginx.service',
        openIncident: true,
      ),
      DeepLinkDestination.unit,
    );
    expect(
      dashboardDeepLinkDestination(
        openTunnels: false,
        openUnitName: null,
        openIncident: true,
      ),
      DeepLinkDestination.incident,
    );
    expect(
      dashboardDeepLinkDestination(
        openTunnels: false,
        openUnitName: '',
        openIncident: false,
      ),
      DeepLinkDestination.none,
    );
  });

  test('unit focus match', () {
    expect(unitFocusFound(['nginx.service'], 'nginx.service'), isTrue);
    expect(unitFocusFound(['sshd.service'], 'nginx.service'), isFalse);
    expect(unitFocusFound(['nginx.service'], null), isFalse);
  });
}
