import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/ssh/hardware_agent.dart';
import 'package:kelola/data/ssh/hardware_identity.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';
import 'package:kelola/data/ssh/ssh_wire.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/domain/hosts/host.dart';

class _FakeSigner implements HardwareSigner {
  _FakeSigner(this.der);

  final Uint8List der;
  final signed = <Uint8List>[];

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    signed.add(data);
    return der;
  }

  @override
  Future<bool> keyExists(String alias) async => true;

  @override
  Future<HardwareKey> generateKey(String alias) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteKey(String alias) async {}

  @override
  Future<void> confirmPresence({String reason = 'Confirm destructive action'}) {
    throw UnimplementedError();
  }
}

Uint8List _requestIdentities() {
  final w = SshWireWriter()..writeUint8(SSHAgentProtocol.requestIdentities);
  return w.takeBytes();
}

Uint8List _signRequest(Uint8List keyBlob, Uint8List data) {
  final w = SshWireWriter()
    ..writeUint8(SSHAgentProtocol.signRequest)
    ..writeString(keyBlob)
    ..writeString(data)
    ..writeUint32(0);
  return w.takeBytes();
}

void main() {
  test('host agent forwarding defaults off', () {
    const host = Host(
      id: 'h1',
      alias: 'web',
      address: '10.0.0.8',
      port: 22,
      username: 'ops',
      keyAlias: 'kelola',
    );
    expect(host.agentForward, isFalse);
  });

  test('session pool attaches the hardware agent only on key sessions', () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(src, contains('HardwareSshAgent'));
    expect(src, contains('usePassword || !host.agentForward'));
  });

  test('agent lists the StrongBox identity and signs only that blob', () async {
    // Minimal valid DER SEQUENCE of two INTEGERs (r=1, s=1).
    final der = Uint8List.fromList([
      0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01,
    ]);
    final blob = OpensshEcdsaP256.publicBlobFromPoint(
      Uint8List.fromList([0x04, ...List<int>.filled(64, 1)]),
    );
    final signer = _FakeSigner(der);
    final identity = HardwareSshIdentity(
      signer: signer,
      alias: 'kelola',
      publicBlob: blob,
      comment: 'kelola',
    );
    final agent = HardwareSshAgent(identity);

    final listed = await agent.handleRequest(_requestIdentities());
    final listReader = SshWireReader(listed);
    expect(listReader.readUint8(), SSHAgentProtocol.identitiesAnswer);
    expect(listReader.readUint32(), 1);
    expect(listReader.readString(), blob);
    expect(listReader.readUtf8(), 'kelola');

    final data = Uint8List.fromList('sign-me'.codeUnits);
    final signed = await agent.handleRequest(_signRequest(blob, data));
    final signReader = SshWireReader(signed);
    expect(signReader.readUint8(), SSHAgentProtocol.signResponse);
    expect(signReader.readString(), isNotEmpty);
    expect(signer.signed, [data]);

    final other = await agent.handleRequest(
      _signRequest(Uint8List.fromList([1, 2, 3]), data),
    );
    expect(SshWireReader(other).readUint8(), SSHAgentProtocol.failure);
    expect(await agent.handleRequest(Uint8List(0)), isNot(equals(signed)));
    expect(
      SshWireReader(await agent.handleRequest(Uint8List(0))).readUint8(),
      SSHAgentProtocol.failure,
    );
  });
}
