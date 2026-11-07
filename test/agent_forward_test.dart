import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/ssh/hardware_agent.dart';
import 'package:kelola/data/ssh/hardware_identity.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';
import 'package:kelola/data/ssh/session_pool.dart';
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

/// A socket the far end has already closed, so login can only fail.
class _ClosedSocket implements SSHSocket {
  final _sent = StreamController<List<int>>()..stream.listen((_) {});

  @override
  Stream<Uint8List> get stream => const Stream.empty();

  @override
  StreamSink<List<int>> get sink => _sent.sink;

  @override
  Future<void> get done => Future.value();

  @override
  Future<void> close() async {}

  @override
  void destroy() {}

  @override
  Future<void> flush() async {}
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
    expect(src, contains('usePassword || !forwardAgent || !host.agentForward'));
    expect(src, contains('_identityFor(host)'));
    expect(src, contains('certificateBlob'));
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
    final agent = HardwareSshAgent(
      identity,
      confirmPresence: () async {},
    )..markAuthenticated();

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

  test('only the Terminal session carries the agent', () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(src, contains('bool forwardAgent = false'));
    expect('forwardAgent: true'.allMatches(src).length, 1);
    final pty = src.indexOf('Future<PtyChannel> openPty(');
    final shell = src.indexOf('await opened.shell(', pty);
    expect(src.indexOf('forwardAgent: true'), inInclusiveRange(pty, shell));
  });

  group('every signature needs presence', () {
    final der = Uint8List.fromList([
      0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01,
    ]);
    final blob = OpensshEcdsaP256.publicBlobFromPoint(
      Uint8List.fromList([0x04, ...List<int>.filled(64, 1)]),
    );
    final data = Uint8List.fromList('sign-me'.codeUnits);
    late _FakeSigner signer;

    HardwareSshAgent agent(Future<void> Function() confirm) {
      signer = _FakeSigner(der);
      return HardwareSshAgent(
        HardwareSshIdentity(
          signer: signer,
          alias: 'kelola',
          publicBlob: blob,
          comment: 'kelola',
        ),
        confirmPresence: confirm,
      )..markAuthenticated();
    }

    int kind(Uint8List reply) => SshWireReader(reply).readUint8();

    test('one prompt per signature, with no carry over', () async {
      var prompts = 0;
      final a = agent(() async => prompts++);
      await a.handleRequest(_signRequest(blob, data));
      await a.handleRequest(_signRequest(blob, data));
      expect(prompts, 2);
      expect(signer.signed, hasLength(2));
    });

    test('a refusal signs nothing and ends further prompts', () async {
      var prompts = 0;
      final a = agent(() async {
        prompts++;
        throw HardwareSignerException('cancelled');
      });
      for (var i = 0; i < 3; i++) {
        expect(
          kind(await a.handleRequest(_signRequest(blob, data))),
          SSHAgentProtocol.failure,
        );
      }
      expect(prompts, 1);
      expect(signer.signed, isEmpty);
    });

    test('listing keys and foreign keys never prompt', () async {
      var prompts = 0;
      final a = agent(() async => prompts++);
      await a.handleRequest(_requestIdentities());
      await a.handleRequest(_signRequest(Uint8List.fromList([1, 2]), data));
      expect(prompts, 0);
    });

    test('requests at once prompt one at a time', () async {
      var open = 0;
      var most = 0;
      final a = agent(() async {
        most = ++open > most ? open : most;
        await Future<void>.delayed(Duration.zero);
        open--;
      });
      await Future.wait([
        a.handleRequest(_signRequest(blob, data)),
        a.handleRequest(_signRequest(blob, data)),
      ]);
      expect(most, 1);
      expect(signer.signed, hasLength(2));
    });

    test('one refusal stops requests already waiting', () async {
      var prompts = 0;
      final a = agent(() async {
        prompts++;
        throw HardwareSignerException('cancelled');
      });
      await Future.wait([
        a.handleRequest(_signRequest(blob, data)),
        a.handleRequest(_signRequest(blob, data)),
      ]);
      expect(prompts, 1);
      expect(signer.signed, isEmpty);
    });

    test('the session pool asks through the signer, naming the host', () {
      final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
      expect(src, contains('confirmPresence: () => _signer.confirmPresence('));
      expect(src, contains("'Let \${host.alias} use your SSH key'"));
    });
  });

  group('nothing is answered before the client has authenticated', () {
    final der = Uint8List.fromList([
      0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01,
    ]);
    final blob = OpensshEcdsaP256.publicBlobFromPoint(
      Uint8List.fromList([0x04, ...List<int>.filled(64, 1)]),
    );
    final data = Uint8List.fromList('sign-me'.codeUnits);
    late _FakeSigner signer;
    late int prompts;

    HardwareSshAgent agent() {
      signer = _FakeSigner(der);
      prompts = 0;
      return HardwareSshAgent(
        HardwareSshIdentity(
          signer: signer,
          alias: 'kelola',
          publicBlob: blob,
          comment: 'kelola',
        ),
        confirmPresence: () async => prompts++,
      );
    }

    int kind(Uint8List reply) => SshWireReader(reply).readUint8();

    test('a sign request is refused with no prompt and no signature', () async {
      final a = agent();
      expect(
        kind(await a.handleRequest(_signRequest(blob, data))),
        SSHAgentProtocol.failure,
      );
      expect(prompts, 0);
      expect(signer.signed, isEmpty);
    });

    test('the key is not listed', () async {
      expect(
        kind(await agent().handleRequest(_requestIdentities())),
        SSHAgentProtocol.failure,
      );
    });

    test('an early request does not stop signing after login', () async {
      final a = agent();
      await a.handleRequest(_signRequest(blob, data));
      a.markAuthenticated();
      expect(
        kind(await a.handleRequest(_signRequest(blob, data))),
        SSHAgentProtocol.signResponse,
      );
      expect(prompts, 1);
      expect(signer.signed, [data]);
    });

    test('a failed login leaves the agent refusing', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final repo = HostRepository(db);
      final a = agent();
      final pool = SshSessionPool(
        repository: repo,
        signer: signer,
        hostKeys: HostKeyPolicy(repo),
        publicBlob: () => blob,
      );
      await expectLater(
        pool.createAndAuthenticateClient(
          socket: _ClosedSocket(),
          username: 'ops',
          identities: const [],
          onVerifyHostKey: (_, _) async => true,
          agentHandler: a,
        ),
        throwsA(anything),
      );
      expect(
        kind(await a.handleRequest(_signRequest(blob, data))),
        SSHAgentProtocol.failure,
      );
      expect(prompts, 0);
    });

    test('the session pool opens the agent only after authentication', () {
      final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
      final authenticated = src.indexOf('await client.authenticated');
      final mark = src.indexOf('agentHandler.markAuthenticated()');
      expect(authenticated, greaterThan(-1));
      expect(mark, greaterThan(authenticated));
      expect(mark, lessThan(src.indexOf('return client;', authenticated)));
    });
  });
}
