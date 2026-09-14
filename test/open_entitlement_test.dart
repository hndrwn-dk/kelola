import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';

void main() {
  test('OpenEntitlement unlocks every feature and purchase is unavailable', () async {
    const entitlement = OpenEntitlement();

    expect(entitlement.isUnlocked(ProFeature.tunnels), isTrue);
    expect(entitlement.isUnlocked(ProFeature.fleetUnlimited), isTrue);
    expect(entitlement.sourceLabel, 'std');
    expect(await entitlement.purchase(), ProPurchaseResult.unavailable);
    expect(await entitlement.restore(), ProPurchaseResult.unavailable);

    entitlement.initialize();
    entitlement.dispose();
    expect(await entitlement.changes.isEmpty, isTrue);
  });
}
