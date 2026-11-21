import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('POSTED comes only from formal ledger, not receipt preferences', () {
    final service = File(
      'lib/features/invoice/invoice_award_formal_income_posting_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();
    expect(service, contains('Future<Set<String>> readPostedIds('));
    expect(service, contains("columns: const <String>['id']"));
    expect(service, contains("where: 'id = ?'"));
    expect(page, contains('_postedLedgerIds.contains('));
    expect(page, contains('await _reloadPostedLedgerState()'));
    expect(page, contains('POSTED（已記帳）'));
    expect(page, contains('if (!_isPosted(readiness) && _receiptFor(readiness) != null)'));
    expect(page, contains('_isPosted(readiness) ||'));
    expect(page, isNot(contains('本版僅預覽，FORMAL_ACCOUNTING_WRITE=ZERO')));
  });

  test('formal ledger keeps atomic no-replace duplicate protection', () {
    final service = File(
      'lib/features/invoice/invoice_award_formal_income_posting_service.dart',
    ).readAsStringSync();
    expect(service, contains('db.transaction<bool>'));
    expect(service, contains('ConflictAlgorithm.abort'));
    expect(service, isNot(contains('ConflictAlgorithm.replace')));
  });
}
