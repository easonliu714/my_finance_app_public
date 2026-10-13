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

  test('4.20.30 keeps full year title independent from long net amount', () {
    final source =
        File('lib/features/account/account_detail_page.dart').readAsStringSync();
    final start = source.indexOf('class _CompactPeriodSummaryCard');
    final end = source.indexOf('class _AccountLedgerTile');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final card = source.substring(start, end);
    expect(card, contains('summary.label'));
    expect(card, contains('_compactMoney(summary.net, currency)'));
    // Separate lines must not force the full '2026年' label to become '20...'.
    expect(card, isNot(contains('Row(')));
    expect(card, contains('BoxFit.scaleDown'));
    // Income/outflow rows may truncate at narrow widths; the period title
    // itself must remain whole and must not use ellipsis.
    final periodTitleStart = card.indexOf('summary.label');
    final periodTitleEnd = card.indexOf('const SizedBox(height: 2)', periodTitleStart);
    expect(periodTitleStart, greaterThanOrEqualTo(0));
    expect(periodTitleEnd, greaterThan(periodTitleStart));
    final periodTitle = card.substring(periodTitleStart, periodTitleEnd);
    expect(periodTitle, isNot(contains('TextOverflow.ellipsis')));
    // The pinned summary adapts its height to device text scaling.
    expect(source, contains('MediaQuery.textScalerOf(context).scale(172.0)'));
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
