import 'package:kelola_pro/src/open_entitlement.dart';
import 'package:kelola_pro/src/pro_feature.dart';

enum ProPurchaseResult { purchased, cancelled, pending, unavailable, error }

abstract class Entitlement {
  /// Synchronous so call sites do not need a FutureBuilder.
  bool isUnlocked(ProFeature feature);

  /// Emitted whenever unlock status changes.
  Stream<void> get changes;

  /// Must not be awaited before runApp. Fire-and-forget; results arrive
  /// on [changes]. Start from the last cached state, not the network.
  void initialize();

  Future<ProPurchaseResult> purchase();
  Future<ProPurchaseResult> restore();

  /// Shown in the hosts colophon so a build can be verified on device.
  /// Stub: 'open-source'. Paid builds: 'play-billing'.
  String get sourceLabel;

  void dispose();
}

/// The only swap point. Do not change this signature without changing both
/// packages.
Entitlement createEntitlement() => OpenEntitlement();
