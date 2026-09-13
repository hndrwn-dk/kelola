abstract class Entitlement {
  bool get tunnelsUnlocked;
}

class OpenEntitlement implements Entitlement {
  const OpenEntitlement();

  @override
  bool get tunnelsUnlocked => true;
}

/// Locked builds / tests — tile stays visible; explainer sheet on tap.
class LockedEntitlement implements Entitlement {
  const LockedEntitlement();

  @override
  bool get tunnelsUnlocked => false;
}
