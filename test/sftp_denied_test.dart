import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/files/sftp_denied.dart';

void main() {
  test('permission denied names the login and keeps the path as snippet', () {
    final copy = sftpDeniedCopy(
      message: 'Permission denied',
      path: '/home/other',
      username: 'hendr',
    );
    expect(copy.title, 'Permission denied');
    expect(copy.body, contains('hendr'));
    expect(copy.body.toLowerCase(), isNot(contains('sudo')));
    expect(copy.snippet, '/home/other');
    expect(looksLikeSftpPermissionDenied('SftpStatusError: Permission denied(code 3)'), isTrue);
    expect(sftpOutsideLoginHome('/home', 'hendr'), isTrue);
    expect(sftpOutsideLoginHome('/home/hendr', 'hendr'), isFalse);
    expect(sftpOutsideLoginHome('/home/hendr/docs', 'hendr'), isFalse);
    expect(
      sftpOutsideHomeWarning(username: 'hendr', path: '/home'),
      contains('hendr'),
    );
  });

  test('other SFTP failures keep the server message in the snippet', () {
    final copy = sftpDeniedCopy(
      message: 'No space left on device',
      path: '/home/hendr/out.bin',
      username: 'hendr',
    );
    expect(copy.title, 'Transfer failed');
    expect(copy.snippet, 'No space left on device');
  });
}
