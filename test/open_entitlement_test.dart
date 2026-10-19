import 'package:flutter_test/flutter_test.dart';
import 'package:kelola_pro/kelola_pro.dart' hide OpenEntitlement;

// The stub that ships in this repo. A path override must not replace the
// sourceLabel this test locks to 'std'.
import '../packages/kelola_pro/lib/src/open_entitlement.dart';

void main() {
  test('OpenEntitlement unlocks every feature and purchase is unavailable', () async {
    const entitlement = OpenEntitlement();

    expect(entitlement.isUnlocked(ProFeature.tunnels), isTrue);
    expect(entitlement.isUnlocked(ProFeature.fleetUnlimited), isTrue);
    expect(entitlement.isUnlocked(ProFeature.fleetWatch), isTrue);
    expect(entitlement.isUnlocked(ProFeature.snippetMulti), isTrue);
    expect(entitlement.isUnlocked(ProFeature.vaultSync), isTrue);
    expect(entitlement.sourceLabel, 'std');
    expect(entitlement.priceLabel, isNull);
    expect(await entitlement.purchase(), ProPurchaseResult.unavailable);
    expect(await entitlement.restore(), ProPurchaseResult.unavailable);

    entitlement.initialize();
    entitlement.dispose();
    expect(await entitlement.changes.isEmpty, isTrue);
  });
}
