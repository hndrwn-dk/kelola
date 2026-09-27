import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:kelola/data/ssh/hardware_identity.dart';
import 'package:kelola/data/ssh/ssh_wire.dart';

/// Offers the StrongBox identity to a remote sshd over agent forwarding.
class HardwareSshAgent implements SSHAgentHandler {
  HardwareSshAgent(this.identity);

  final HardwareSshIdentity identity;

  @override
  Future<Uint8List> handleRequest(Uint8List request) async {
    if (request.isEmpty) {
      return _failure();
    }
    final reader = SshWireReader(request);
    switch (reader.readUint8()) {
      case SSHAgentProtocol.requestIdentities:
        return _identities();
      case SSHAgentProtocol.signRequest:
        return _sign(reader);
      default:
        return _failure();
    }
  }

  Uint8List _identities() {
    final writer = SshWireWriter()
      ..writeUint8(SSHAgentProtocol.identitiesAnswer)
      ..writeUint32(1)
      ..writeString(identity.publicBlob)
      ..writeUtf8(identity.comment);
    return writer.takeBytes();
  }

  Future<Uint8List> _sign(SshWireReader reader) async {
    final keyBlob = reader.readString();
    final data = reader.readString();
    if (!_bytesEqual(keyBlob, identity.publicBlob)) {
      return _failure();
    }
    final signature = await identity.toIdentity().sign(data);
    final writer = SshWireWriter()
      ..writeUint8(SSHAgentProtocol.signResponse)
      ..writeString(signature.encode());
    return writer.takeBytes();
  }

  Uint8List _failure() {
    final writer = SshWireWriter()..writeUint8(SSHAgentProtocol.failure);
    return writer.takeBytes();
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
