/// Whether the Hosts screen shows the What's new card.
///
/// [onboarded] is false until first-run setup (the device key) exists, so a
/// fresh install never sees it. [seen] is the versionName stored when the
/// card was last closed; `''` for upgraders from builds before the card.
/// [version] is the release versionName; `''` in debug builds and tests.
bool whatsNewDue(bool onboarded, String seen, String version) =>
    onboarded && version.isNotEmpty && seen != version;
