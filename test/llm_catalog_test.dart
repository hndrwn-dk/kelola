import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/llm/assist_context.dart';
import 'package:kelola/domain/llm/catalog.dart';
import 'package:kelola/domain/llm/propose.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  const ctx = AssistContext(
    unitNames: ['nginx.service'],
    paths: ['/'],
    hostAlias: 'nas-01',
  );

  test('accepts catalog probe with params from context', () {
    final p = parseProbeProposal(
      '{"probeKind":"unit_restart","unit":"nginx.service"}',
      catalog: assistCatalog,
      context: ctx,
    );
    expect(p.available, isTrue);
    expect(p.probeKind, 'unit_restart');
    expect(p.unit, 'nginx.service');
    expect(p.risk, RiskLevel.mutate);
  });

  test('rejects unit outside loaded context even if in catalog', () {
    final p = parseProbeProposal(
      '{"probeKind":"unit_restart","unit":"sshd.service"}',
      catalog: assistCatalog,
      context: ctx,
    );
    expect(p.available, isFalse);
    expect(p.message, 'tidak ada aksi tersedia');
  });

  test('rejects unknown probeKind', () {
    final p = parseProbeProposal(
      '{"probeKind":"rm_rf","unit":"nginx.service"}',
      catalog: assistCatalog,
      context: ctx,
    );
    expect(p.available, isFalse);
  });

  test('rejects path outside loaded context', () {
    final p = parseProbeProposal(
      '{"probeKind":"df_pt","path":"/var"}',
      catalog: assistCatalog,
      context: ctx,
    );
    expect(p.available, isFalse);
    expect(p.message, 'tidak ada aksi tersedia');
  });

  test('accepts path from loaded context', () {
    final p = parseProbeProposal(
      '{"probeKind":"df_pt","path":"/"}',
      catalog: assistCatalog,
      context: ctx,
    );
    expect(p.available, isTrue);
    expect(p.path, '/');
  });

  test('lockout unit in context still carries destructive risk from catalog', () {
    final lockoutCtx = AssistContext(
      unitNames: const ['sshd.service'],
      paths: const ['/'],
      hostAlias: 'nas-01',
    );
    final p = parseProbeProposal(
      '{"probeKind":"unit_restart","unit":"sshd.service"}',
      catalog: assistCatalog,
      context: lockoutCtx,
    );
    expect(p.available, isTrue);
    expect(p.risk, RiskLevel.destructive);
  });
}
