import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('general award result is published before cloud native refresh', () {
    final source = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();

    final generalEvaluate = source.indexOf(
      'final generalEvaluations = dataset == null',
    );
    final generalPublish = source.indexOf(
      '_generalEvaluations = generalEvaluations;',
    );
    final cloudRefresh = source.indexOf(
      'cloudRefresh = await cloudService.refresh(',
    );

    expect(generalEvaluate, greaterThanOrEqualTo(0));
    expect(generalPublish, greaterThan(generalEvaluate));
    expect(cloudRefresh, greaterThan(generalPublish));
    expect(
      source,
      contains('General awards and cloud-exclusive awards are independent authority'),
    );
    expect(source, contains('一般獎對獎結果已保留；雲端專屬獎未完成。'));
  });
}
