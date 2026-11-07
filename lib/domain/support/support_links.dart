const kKelolaPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.tursinalabs.kelola';
const kKelolaPrivacyUrl = 'https://www.tursinalabs.com/kelola/privacy';
const kKelolaTermsUrl = 'https://www.tursinalabs.com/kelola/terms';

const kKelolaShareSubject = 'Kelola';
const kKelolaShareText =
    'Kelola — agentless Linux admin from your phone.\n$kKelolaPlayStoreUrl';

class SupportFaqItem {
  const SupportFaqItem({required this.question, required this.answer});

  final String question;
  final String answer;
}

const kSupportFaq = <SupportFaqItem>[
  SupportFaqItem(
    question: 'How do I add a server?',
    answer:
        'On Hosts, tap Add host and enter the address, user and port. Kelola talks to it over SSH. Nothing is installed on the server.',
  ),
  SupportFaqItem(
    question: 'How does the phone get access to a server?',
    answer:
        "Copy this phone's public key into ~/.ssh/authorized_keys, or use your password once to let Kelola install it. The password is not stored. Root login is refused.",
  ),
  SupportFaqItem(
    question: 'Why does a new host ask me to confirm a fingerprint?',
    answer:
        'The first connection pins the server key. If that key changes later, Kelola blocks the connection, because the server may not be the one you added.',
  ),
  SupportFaqItem(
    question: 'Where are my SSH keys?',
    answer:
        'The key is created in this phone\'s secure key store and cannot be copied out, even in a vault export. A new phone needs its own key added to each server.',
  ),
  SupportFaqItem(
    question: 'Why does an action say sudo needs a password?',
    answer:
        'Kelola never asks for a sudo password during daily use. Actions that change a host need passwordless sudo. Tap Enable Kelola sudo to review and add the rules once. On hosts with sudo-rs or older sudo it adds service rules one action at a time.',
  ),
  SupportFaqItem(
    question: 'What are tags and Environments?',
    answer:
        'Tag hosts on Edit host, for example prod or uat. Settings → Environments sets variables for every host with a tag. Search finds hosts by tag, and Run on hosts can select them by tag.',
  ),
  SupportFaqItem(
    question: 'What does AI Assist send?',
    answer:
        'Nothing unless you turn it on and tap Explain, Summarise or Propose. Host names, addresses and users are redacted, and a public endpoint shows you the exact text first. AI suggestions never run on their own.',
  ),
  SupportFaqItem(
    question: 'What does vault export include?',
    answer:
        'Hosts, snippets, and settings. Passwords, env values, and snippet bodies stay off the blob unless you turn on include secrets.',
  ),
  SupportFaqItem(
    question: 'How does app lock work?',
    answer:
        'Optional. Uses the device screen lock. If the platform errors, Kelola stays locked. While it is on, screenshots are blocked unless you allow them in Settings → Screenshots.',
  ),
  SupportFaqItem(
    question: 'Where do downloaded files go?',
    answer:
        'Into Kelola\'s private storage on this phone, in kelola-transfers. Other apps cannot read them there.',
  ),
  SupportFaqItem(
    question: 'What does Kelola Pro add?',
    answer:
        'A one-time unlock for tunnels, unlimited fleet hosts, running snippets on several hosts, and vault sync. Restore purchase brings it back on the same Google account.',
  ),
  SupportFaqItem(
    question: 'How do I report a problem?',
    answer:
        'Settings → Rate & review opens the Play listing. Use the review field there.',
  ),
];
