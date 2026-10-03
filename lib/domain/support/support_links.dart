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
        'On Hosts, add a host (address, user, port). Kelola talks to it over SSH. Nothing is installed on the server.',
  ),
  SupportFaqItem(
    question: 'Where are my SSH keys?',
    answer:
        'Keys stay on this phone. They are not uploaded and are not in a default vault export.',
  ),
  SupportFaqItem(
    question: 'What does vault export include?',
    answer:
        'Hosts, snippets, and settings. Passwords, env values, and snippet bodies stay off the blob unless you turn on include secrets.',
  ),
  SupportFaqItem(
    question: 'How does app lock work?',
    answer:
        'Optional. Uses the device screen lock. If the platform errors, Kelola stays locked.',
  ),
  SupportFaqItem(
    question: 'How do I report a problem?',
    answer:
        'Settings → Rate & review opens the Play listing. Use the review field there.',
  ),
];
