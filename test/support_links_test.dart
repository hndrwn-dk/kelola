import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/support/support_links.dart';

void main() {
  test('support URLs and share text use the Play listing and legal pages', () {
    expect(
      kKelolaPlayStoreUrl,
      'https://play.google.com/store/apps/details?id=com.tursinalabs.kelola',
    );
    expect(
      kKelolaPrivacyUrl,
      'https://www.tursinalabs.com/kelola/privacy',
    );
    expect(
      kKelolaTermsUrl,
      'https://www.tursinalabs.com/kelola/terms',
    );
    expect(kKelolaShareSubject, 'Kelola');
    expect(kKelolaShareText, contains(kKelolaPlayStoreUrl));
    expect(kKelolaShareText, contains('agentless Linux admin'));
    expect(Uri.parse(kKelolaPlayStoreUrl).isAbsolute, isTrue);
    expect(Uri.parse(kKelolaPrivacyUrl).isAbsolute, isTrue);
    expect(Uri.parse(kKelolaTermsUrl).isAbsolute, isTrue);
  });

  test('FAQ has the five Tester Community questions', () {
    expect(kSupportFaq, hasLength(5));
    expect(
      kSupportFaq.map((item) => item.question).toList(),
      [
        'How do I add a server?',
        'Where are my SSH keys?',
        'What does vault export include?',
        'How does app lock work?',
        'How do I report a problem?',
      ],
    );
    expect(kSupportFaq[0].answer, contains('Nothing is installed on the server'));
    expect(kSupportFaq[4].answer, contains('Rate & review'));
  });
}
