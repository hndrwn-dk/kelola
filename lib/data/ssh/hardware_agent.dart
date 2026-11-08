import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:kelola/data/ssh/hardware_identity.dart';
import 'package:kelola/data/ssh/ssh_wire.dart';

/// Offers the StrongBox identity to a remote sshd over agent forwarding.
///
/// The one key opens every host, so a forwarded signature is a login to any of
/// them. Each signature needs fresh presence: the key's own auth window would
/// let this host sign silently. Prompts run one at a time. A refusal or a
/// failed prompt ends signing on this connection, so a host cannot keep asking
/// until the user gives in.
///
/// dartssh2 accepts agent channels as soon as the client exists, so every
/// request is refused until [markAuthenticated]. A host could otherwise ask
/// during login, while the user is answering the login prompt.
class HardwareSshAgent implements SSHAgentHandler {
  HardwareSshAgent(this.identity, {required this.confirmPresence});

  final HardwareSshIdentity identity;

  /// Completes once the user has confirmed, and throws if they did not.
  final Future<void> Function() confirmPresence;

  Future<void> _lastPrompt = Future.value();
  var _refused = false;
  var _authenticated = false;

  /// Call once the client has authenticated. Never called if login fails.
  void markAuthenticated() {
    _authenticated = true;
  }

  @override
  Future<Uint8List> handleRequest(Uint8List request) async {
    if (!_authenticated || request.isEmpty) {
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
    if (!await _approve()) {
      return _failure();
    }
    final signature = await identity.toIdentity().sign(data);
    final writer = SshWireWriter()
      ..writeUint8(SSHAgentProtocol.signResponse)
      ..writeString(signature.encode());
    return writer.takeBytes();
  }

  Future<bool> _approve() {
    final approved = _lastPrompt.then((_) async {
      if (_refused) {
        return false;
      }
      try {
        await confirmPresence();
        return true;
      } catch (_) {
        _refused = true;
        return false;
      }
    });
    _lastPrompt = approved;
    return approved;
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
