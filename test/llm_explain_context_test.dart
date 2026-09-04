import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/llm/explain_context.dart';
import 'package:kelola/domain/units/service_unit.dart';

void main() {
  test('formatUnitShowForAssist includes Result and ExecMainStatus', () {
    const detail = UnitDetail(
      name: 'nginx.service',
      properties: {
        'Id': 'nginx.service',
        'ActiveState': 'failed',
        'SubState': 'failed',
        'Result': 'exit-code',
        'ExecMainStatus': '1',
        'ExecMainCode': 'exited',
        'Description': 'A high performance web server',
      },
      logs: 'nginx: [emerg] invalid directive\nother noise',
      dependencies: '',
    );
    final show = formatUnitShowForAssist(detail);
    expect(show, contains('Result=exit-code'));
    expect(show, contains('ExecMainStatus=1'));
    expect(show, contains('ActiveState=failed'));
    expect(
      journalLinesFromUnitDetail(detail),
      ['nginx: [emerg] invalid directive', 'other noise'],
    );
  });
}
