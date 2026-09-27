import 'package:kelola/domain/vault/vault_transport.dart';

class MemoryVaultTransport implements VaultTransport {
  MemoryVaultTransport({this.blob});

  List<int>? blob;

  @override
  VaultTransportKind get kind => VaultTransportKind.file;

  @override
  Future<void> write(List<int> next) async {
    blob = List<int>.from(next);
  }

  @override
  Future<List<int>> read() async {
    final current = blob;
    if (current == null) {
      throw StateError('No vault blob');
    }
    return current;
  }
}
