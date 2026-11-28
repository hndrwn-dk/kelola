import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/argocd/argo_app.dart';
import 'package:kelola/domain/argocd/argo_parser.dart';

String _fixture(String name) =>
    File('test/fixtures/argocd/$name').readAsStringSync();

final _readAt = DateTime.utc(2026, 11, 10, 9, 6);

ArgoApps _parse(String stdout) => parseArgoApps(stdout, readAt: _readAt);

ArgoApps _parseJson(String name) => _parse('---APPS---\n${_fixture(name)}\n');

void main() {
  group('fixtures', () {
    test('every synthetic JSON fixture is marked', () {
      final dir = Directory('test/fixtures/argocd');
      for (final f in dir.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (!name.startsWith('apps_')) {
          continue;
        }
        final text = f.readAsStringSync();
        if (name.endsWith('.json')) {
          expect(text, contains('"_synthetic": true'), reason: name);
        } else {
          expect(text, startsWith('# synthetic'), reason: name);
        }
      }
    });
  });

  group('parseArgoApps errors', () {
    test('a junk APPS body never reaches the error text', () {
      final r = _parse('---APPS---\noops-raw-line\n{"half": \n');
      expect(r.apps, isEmpty);
      expect(r.error, 'unreadable output');
      expect(r.error, isNot(contains('oops-raw-line')));
    });

    test('junk fixture sets an error and no apps', () {
      final r = _parse(_fixture('apps_junk.txt'));
      expect(r.apps, isEmpty);
      expect(r.error, isNotNull);
      expect(r.error, isNot(contains('oops')));
      expect(r.error, isNot(contains('half')));
    });

    test('forbidden fixture gives Forbidden and no apps', () {
      final r = _parse(_fixture('apps_forbidden.txt'));
      expect(r.apps, isEmpty);
      expect(r.error, 'Forbidden');
    });

    test('error comes only from the APPS_ERR section', () {
      final r = _parse(
        '---APPS---\nsecret-looking-body\n---APPS_ERR---\n'
        'KELOLA_ERR error: the server doesn\'t have a resource type "applications"\n',
      );
      expect(r.error, 'NotFound');
    });

    test('no APPS section at all is "no output"', () {
      expect(_parse('').error, 'no output');
      expect(_parse('garbage\nmore').error, 'no output');
    });

    test('NO_KUBECTL marker is "no kubectl"', () {
      final r = _parse('---NO_KUBECTL---\n');
      expect(r.error, 'no kubectl');
      expect(r.apps, isEmpty);
    });

    test('JSON without an items list is an error, never an empty list', () {
      final r = _parse('---APPS---\n{"kind":"Status","status":"Failure"}\n');
      expect(r.error, 'unreadable output');
      expect(r.apps, isEmpty);
    });

    test('JSON followed by a KELOLA_ERR line still parses', () {
      final json = _fixture('apps_guestbook_synced.json');
      final inBody = _parse('---APPS---\n$json\nKELOLA_ERR warning: x\n');
      expect(inBody.error, isNull);
      expect(inBody.apps.single.name, 'guestbook');
      final inErr = _parse(
        '---APPS---\n$json\n---APPS_ERR---\nKELOLA_ERR warning: x\n',
      );
      expect(inErr.error, isNull);
      expect(inErr.apps.single.name, 'guestbook');
    });

    test('readAt is carried through', () {
      expect(_parse('').readAt, _readAt);
    });
  });

  group('reader denied', () {
    test('READER_DENIED marker sets readerDenied', () {
      final json = _fixture('apps_guestbook_synced.json');
      final r = _parse('---READER_DENIED---\n---APPS---\n$json\n');
      expect(r.readerDenied, isTrue);
      expect(r.apps, hasLength(1));
    });

    test('absent marker leaves readerDenied false', () {
      expect(_parseJson('apps_guestbook_synced.json').readerDenied, isFalse);
      expect(ArgoApps(apps: const [], readAt: _readAt).readerDenied, isFalse);
    });
  });

  group('guestbook fields', () {
    late ArgoApp app;
    setUpAll(() {
      final r = _parseJson('apps_guestbook_synced.json');
      expect(r.error, isNull);
      app = r.apps.single;
    });

    test('metadata and spec', () {
      expect(app.name, 'guestbook');
      expect(app.namespace, 'argocd');
      expect(app.project, 'default');
      expect(app.destServer, 'https://kubernetes.default.svc');
      expect(app.destNamespace, 'guestbook');
      expect(app.automated, isTrue);
      expect(app.prune, isTrue);
      expect(app.selfHeal, isTrue);
    });

    test('source', () {
      final s = app.sources.single;
      expect(
        s.repoUrl,
        'https://github.com/argoproj/argocd-example-apps.git',
      );
      expect(s.path, 'guestbook');
      expect(s.chart, isNull);
      expect(s.targetRevision, 'HEAD');
      expect(s.kind, 'git');
    });

    test('status', () {
      expect(app.sync, ArgoSync.synced);
      expect(app.health, ArgoHealth.healthy);
      expect(app.syncedRevisions, [
        '723b86e01bea11dcf72316cb172868fcbf05d69e',
      ]);
      expect(app.syncedRevision, '723b86e');
      expect(app.opPhase, ArgoOpPhase.succeeded);
      expect(app.opMessage, 'successfully synced (all tasks run)');
      expect(app.opStartedAt, DateTime.utc(2026, 11, 10, 9, 0, 5));
      expect(app.opFinishedAt, DateTime.utc(2026, 11, 10, 9, 0, 8));
      expect(app.reconciledAt, DateTime.utc(2026, 11, 10, 9, 5));
      expect(app.conditions, isEmpty);
    });

    test('resources', () {
      expect(app.resources, hasLength(2));
      final svc = app.resources[0];
      expect(svc.group, '');
      expect(svc.kind, 'Service');
      expect(svc.namespace, 'guestbook');
      expect(svc.name, 'guestbook-ui');
      expect(svc.sync, ArgoSync.synced);
      expect(svc.health, ArgoHealth.healthy);
      expect(svc.healthMessage, isNull);
      expect(svc.requiresPruning, isFalse);
      expect(app.resources[1].group, 'apps');
      expect(app.resources[1].kind, 'Deployment');
    });

    test('history newest first with short revisions', () {
      expect(app.history.map((h) => h.id), [1, 0]);
      expect(app.history.first.revision, '723b86e');
      expect(app.history.first.deployedAt, DateTime.utc(2026, 11, 10, 9, 0, 8));
      expect(app.history.last.revision, '53e28ff');
    });

    test('rowMeta', () {
      expect(app.rowMeta, 'Synced · Healthy · 723b86e');
    });
  });

  group('other fixtures', () {
    test('manual out of sync, destination name, pruning resource', () {
      final app = _parseJson('apps_outofsync_manual.json').apps.single;
      expect(app.sync, ArgoSync.outOfSync);
      expect(app.automated, isFalse);
      expect(app.prune, isFalse);
      expect(app.selfHeal, isFalse);
      expect(app.destServer, 'in-cluster');
      expect(app.project, 'infra');
      expect(app.resources.last.requiresPruning, isTrue);
      expect(app.resources.last.health, ArgoHealth.unknown);
      expect(app.opPhase, ArgoOpPhase.none);
    });

    test('sync failed: condition and op phase', () {
      final app = _parseJson('apps_sync_failed.json').apps.single;
      expect(app.opPhase, ArgoOpPhase.failed);
      expect(app.automated, isTrue);
      expect(app.prune, isFalse);
      expect(app.conditions.single.type, 'ComparisonError');
      expect(app.conditions.single.message, contains('app path does not exist'));
      expect(app.sync, ArgoSync.unknown);
      expect(app.syncedRevision, isNull);
    });

    test('degraded with a resource health message', () {
      final app = _parseJson('apps_degraded.json').apps.single;
      expect(app.health, ArgoHealth.degraded);
      expect(
        app.resources.single.healthMessage,
        'Deployment "bad-image" exceeded its progress deadline',
      );
      expect(app.syncedRevision, 'v1.4.0');
    });

    test('multi-source: two sources, two revisions', () {
      final app = _parseJson('apps_multisource.json').apps.single;
      expect(app.sources, hasLength(2));
      expect(app.sources[0].chart, 'redis');
      expect(app.sources[0].path, isNull);
      expect(app.sources[0].kind, 'helm');
      expect(app.sources[0].targetRevision, '19.6.4');
      expect(app.sources[1].path, 'redis/overlays/lab');
      expect(app.sources[1].kind, 'git');
      expect(app.sources[1].targetRevision, 'HEAD');
      expect(app.syncedRevisions, [
        '19.6.4',
        'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0',
      ]);
      expect(app.syncedRevision, '19.6.4');
      expect(app.history.first.id, 4);
      expect(app.history.first.revision, '19.6.4');
    });

    test('missing status maps to unknown / none without throwing', () {
      final r = _parse(
        '---APPS---\n{"items":[{"metadata":{"name":"bare","namespace":"argocd"},'
        '"spec":{"project":"default"}}]}\n',
      );
      final app = r.apps.single;
      expect(app.sync, ArgoSync.unknown);
      expect(app.health, ArgoHealth.unknown);
      expect(app.opPhase, ArgoOpPhase.none);
      expect(app.sources, isEmpty);
      expect(app.resources, isEmpty);
      expect(app.history, isEmpty);
      expect(app.reconciledAt, isNull);
      expect(app.syncedRevision, isNull);
    });

    test('wrong types and unknown strings never throw', () {
      final r = _parse(
        '---APPS---\n{"items":[{"metadata":{"name":"odd"},'
        '"spec":{"source":"nope","syncPolicy":{"automated":true}},'
        '"status":{"health":{"status":"Weird"},"sync":{"status":"Sideways"},'
        '"operationState":{"phase":"Dancing"},"resources":[1,"x",{"kind":5}],'
        '"history":[{"id":"x"}],"conditions":"no"}},"junk"]}\n',
      );
      final app = r.apps.single;
      expect(app.health, ArgoHealth.unknown);
      expect(app.sync, ArgoSync.unknown);
      expect(app.opPhase, ArgoOpPhase.none);
      expect(app.resources, hasLength(1));
      expect(app.resources.single.kind, '');
    });

    test('300 resources parse', () {
      final app = _parseJson('apps_300_resources.json').apps.single;
      expect(app.resources, hasLength(300));
      expect(app.resources.first.name, 'svc-000');
      expect(app.resources.last.name, 'svc-299');
    });

    test('OpenShift GitOps when every app lives in openshift-gitops', () {
      final r = _parseJson('apps_openshift_gitops.json');
      expect(r.apps, hasLength(2));
      expect(r.openShiftGitOps, isTrue);
      expect(_parseJson('apps_guestbook_synced.json').openShiftGitOps, isFalse);
      expect(_parse('---APPS---\n{"items":[]}\n').openShiftGitOps, isFalse);
    });

    test('empty items is a real empty list without error', () {
      final r = _parse('---APPS---\n{"apiVersion":"v1","items":[],"kind":"List"}\n');
      expect(r.error, isNull);
      expect(r.apps, isEmpty);
    });
  });

  group('secrets', () {
    const secrets = [
      's3cr3t-helm-value',
      'p4ram-secret',
      'plugin-env-secret',
      'kustomize-patch-secret',
      'info-secret',
      'fp-secret-file',
      'jsonnet-ext-secret',
      'jsonnet-tla-secret',
    ];

    test('helm fixture parses and no secret survives in toString', () {
      final r = _parseJson('apps_helm_secrets.json');
      expect(r.error, isNull);
      expect(r.apps, hasLength(2));
      expect(r.apps[0].sources.single.chart, 'payments');
      expect(r.apps[1].sources, hasLength(3));
      for (final app in r.apps) {
        final text = app.toString();
        expect(text, contains(app.name));
        for (final s in secrets) {
          expect(text, isNot(contains(s)), reason: '${app.name} leaks $s');
        }
      }
    });

    test('token URL fixture is stripped', () {
      final app = _parseJson('apps_token_url.json').apps.single;
      expect(app.sources.single.repoUrl, 'https://github.com/o/r.git');
      expect(app.sources.single.targetRevision, 'HEAD');
      expect(app.toString(), isNot(contains('ghp_x')));
      expect(app.toString(), isNot(contains('token=y')));
    });

    test('stripRepoCredentials', () {
      expect(
        stripRepoCredentials('https://ghp_x@github.com/o/r.git?token=y'),
        'https://github.com/o/r.git',
      );
      expect(stripRepoCredentials('https://user:pw@host/x'), 'https://host/x');
      expect(stripRepoCredentials('https://host/x#frag'), 'https://host/x');
      expect(
        stripRepoCredentials('http://u:p@ss@host:8080/x'),
        'http://host:8080/x',
      );
      expect(
        stripRepoCredentials('oci://tok@ghcr.io/o/charts'),
        'oci://ghcr.io/o/charts',
      );
      expect(
        stripRepoCredentials('ssh://git@github.com/o/r.git'),
        'ssh://git@github.com/o/r.git',
      );
      expect(stripRepoCredentials('ssh://git:pw@h/r'), 'ssh://git@h/r');
      expect(
        stripRepoCredentials('git@github.com:o/r.git'),
        'git@github.com:o/r.git',
      );
      expect(
        stripRepoCredentials('user:pw@host:path/r.git'),
        'user@host:path/r.git',
      );
      expect(
        stripRepoCredentials('https://github.com/o/r.git'),
        'https://github.com/o/r.git',
      );
      expect(stripRepoCredentials('ghcr.io/o/charts'), 'ghcr.io/o/charts');
      expect(stripRepoCredentials('weird//tok@host/x'), 'host/x');
      expect(stripRepoCredentials(''), '');
    });

    test('shortRevision', () {
      expect(
        shortRevision('723b86e01bea11dcf72316cb172868fcbf05d69e'),
        '723b86e',
      );
      expect(shortRevision('v1.4.0'), 'v1.4.0');
      expect(shortRevision('19.6.4'), '19.6.4');
      expect(shortRevision('abc'), 'abc');
      expect(shortRevision(''), '');
    });
  });
}
