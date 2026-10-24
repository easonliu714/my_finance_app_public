import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('award page exposes tappable winner summary and clear cloud eligibility copy', () {
    final source = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();

    expect(source, contains("'中獎摘要'"));
    expect(source, contains('invoice_award_winner_jump_'));
    expect(source, contains('Scrollable.ensureVisible'));
    expect(source, contains('雲端專屬獎資格怎麼看？'));
    expect(source, contains('開獎前已列印證明聯'));
    expect(source, contains('開獎後才列印中獎證明聯'));
    expect(source, contains('遺失後不能再重印'));
  });
}
