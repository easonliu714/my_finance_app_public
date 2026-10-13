import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4.20.28 geometry anchor must never assume fixed tile heights', () {
    final source = File('lib/features/account/account_detail_page.dart').readAsStringSync();
    expect(source, contains('RenderSliverList'));
    expect(source, contains('sliver.indexOf(row)'));
    expect(source, contains('sliver.childAfter(row)'));
    expect(source, isNot(contains('offset / _ledgerTileApproxHeight')));
    expect(source, contains("label: '\${anchor.year}年'"));
    expect(source, contains(".padLeft(2, '0')}月'"));
    expect(source, contains('來源／稽核資訊'));
    expect(source, contains('ValueKey<String>(item.id)'));
  });

  test('4.20.28 award policies hidden behind accessible on-demand help', () {
    final source = File('lib/features/invoice/invoice_award_production_page.dart').readAsStringSync();
    expect(source, contains('Icons.help_outline'));
    expect(source, isNot(contains("title: _helpTitle('中獎結果通知'")));
    expect(source, contains("_awardHelpButton('中獎結果通知'"));
    expect(source, contains('showModalBottomSheet<void>'));
    expect(source, contains('自動更新官方獎號'));
    expect(source, contains('中獎結果通知'));
    expect(source, contains('中獎獎金自動記帳準備'));
    expect(source, contains('確認新增正式發票兌獎收入'));
    expect(source, contains('POSTED（已記帳）'));
    expect(source, contains('_postConfirmedBankCredit(readiness)'));
    expect(source, contains('_confirmBankCredit(readiness)'));
  });
}
