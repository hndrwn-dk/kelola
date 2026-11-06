/// Copy for the Hosts screen What's new card.
///
/// [notes] must equal the lines of `docs/store/whatsnew/whatsnew-en-US`
/// without the leading `- ` (`test/whats_new_test.dart` checks it). A
/// release PR replaces both; other PRs leave both alone. At most three
/// short notes so NEEDS ATTENTION stays on the first screen.
abstract final class WhatsNewStrings {
  static const title = "What's new in Kelola";
  static const close = 'Close';

  static String label(String version) => "What's new · $version";

  static const notes = <String>[
    'Packages opens instantly from the last list for each host.',
    'OKD clusters are labelled OKD, not OpenShift.',
    'Files refuses unsafe file names sent by a server.',
  ];
}
