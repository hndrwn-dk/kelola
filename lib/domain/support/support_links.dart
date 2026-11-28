import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';

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
        'Kelola never asks for a sudo password during daily use. Actions that change a host need passwordless sudo. Tap Enable Kelola sudo to review and add the rules once. $kelolaServicesFoundNote $kelolaServicesConfigAsRootNote Kelola adds nginx and Apache service lines only when their config is root-owned and not writable by others.',
  ),
  SupportFaqItem(
    question: 'What are tags and tag variables?',
    answer:
        'Tag hosts on Edit host, for example prod or uat. Search finds hosts by tag, and Run on hosts can select them by tag. Settings → Tag variables sets values such as REGION for every host with a tag, and commands and snippets can use them as \$REGION.',
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
    question: 'Service lenses',
    answer:
        'When a host\'s dashboard opens (at most every 15 minutes, or on pull-to-refresh), Kelola detects nginx, Apache httpd, MariaDB, MySQL and PostgreSQL. Web servers appear in a STACK section; database lenses are not in this version.\n\n'
        'The web lens reads the config test, vhosts, certificate expiry, the error log tail and access-log status codes. It never reads private keys. Reads run as your login first, then sudo -n.\n\n'
        'If a section needs root, it shows as unreadable and you can tap Enable Kelola sudo, the same one tap as for packages and firewall. It also writes the exact lens commands to /etc/sudoers.d/kelola-web and checks the file with visudo. A certificate or log in a directory that is not root-owned, or that others can write, is not granted.\n\n'
        'The config test runs the web server as root, and it loads the modules its config names. Before adding it, Kelola checks on the host that the config, every file it includes and the module directories are root-owned and not writable by others, and leaves the config test out (saying which path failed) when they are not. No grant is offered on read-only hosts.\n\n'
        'Reload tests the config first and reloads only if the test passes. It is off on read-only hosts. On systemd hosts a missing reload permission can be granted per service. On OpenRC Kelola shows the sudoers hint and you add the rule yourself.\n\n'
        'Fleet shows a filter pill for each detected service, from hosts you have already opened.',
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
