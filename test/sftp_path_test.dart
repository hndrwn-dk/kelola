import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/files/sftp_path.dart';

void main() {
  test('join keeps absolute child and collapses parent segments', () {
    expect(joinSftpPath('/home/u', 'foo'), '/home/u/foo');
    expect(joinSftpPath('/home/u', '..'), '/home');
    expect(joinSftpPath('/', '..'), '/');
    expect(joinSftpPath('/home/u', '/etc'), '/etc');
    expect(joinSftpPath('/home/u', './a/../b'), '/home/u/b');
  });

  test('basename parent and bak stay on the remote path', () {
    expect(sftpBasename('/a/b/c'), 'c');
    expect(sftpBasename('/'), '/');
    expect(sftpParent('/a/b/c'), '/a/b');
    expect(sftpParent('/'), '/');
    expect(sftpBakPath('/etc/nginx/nginx.conf'), '/etc/nginx/nginx.conf.bak');
  });
}
