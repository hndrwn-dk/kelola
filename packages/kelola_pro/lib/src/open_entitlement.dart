import 'package:kelola_pro/src/entitlement.dart';
import 'package:kelola_pro/src/pro_feature.dart';

class OpenEntitlement implements Entitlement {
  const OpenEntitlement();

  @override
  bool isUnlocked(ProFeature feature) => true;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  void initialize() {}

  @override
  Future<ProPurchaseResult> purchase() async => ProPurchaseResult.unavailable;

  @override
  Future<ProPurchaseResult> restore() async => ProPurchaseResult.unavailable;

  @override
  String get sourceLabel => 'std';

  @override
  void dispose() {}
}
