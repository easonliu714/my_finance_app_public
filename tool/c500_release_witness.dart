// CI-only release-AOT entrypoint. Never bundled by production main().
 // No user data, official PDF download, production signing or formal DB writes.
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud500_production_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_award_check_presentation.dart';
import 'package:my_finance_app/features/invoice/invoice_award_match_projection.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_index_lkg_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_index.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_award_remittance_receipt_evidence.dart';
import 'package:my_finance_app/features/invoice/invoice_award_formal_income_posting_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    home: Scaffold(body: Center(child: Text('C500 release safety witness'))),
  ));
  unawaited(_runWitness());
}

Future<void> _runWitness() async {
  Directory? sandbox;
  try {
    _require(kReleaseMode, 'NOT_RELEASE_AOT');
    final sandboxDir = await Directory.systemTemp.createTemp('c500-release-witness-');
    sandbox = sandboxDir;

    // Historical C500 must not render; independently authorized tiers remain.
    const presenter = InvoiceAwardCheckPresentationBuilder();
    _require(presenter.build(_projection(500, '雲端發票專屬獎 500 元',
        InvoiceAwardProjectionDomain.cloudExclusive)) == null,
        'LEGACY_CLOUD500_UI_REAUTHORIZED');
    _require(presenter.build(_projection(800, '雲端發票專屬獎 800 元',
        InvoiceAwardProjectionDomain.cloudExclusive)) != null,
        'CLOUD800_REGRESSION');
    _require(presenter.build(_projection(200, '六獎',
        InvoiceAwardProjectionDomain.general)) != null,
        'GENERAL_AWARD_REGRESSION');

    // Direct LKG calls must reject before reading or writing any root files.
    var rootCalls = 0;
    final lkg = CloudAwardIndexLkgRepository(
      supportDirectoryProvider: () async {
        rootCalls += 1;
        return sandboxDir;
      },
    );
    final candidate = File('${sandboxDir.path}/legacy.index');
    await candidate.writeAsString('AA12345678\n', flush: true);
    final originalCandidate = await candidate.readAsBytes();
    _require(await lkg.readLatest(periodId: '115-05-06',
        tierCode: 'cloud-500') == null && rootCalls == 0,
        'LEGACY_CLOUD500_LKG_READ_REAUTHORIZED');
    await _expectDeferred(() => lkg.promoteValidated(
      build: CloudAwardIndexBuildResult(
        candidateIndexFile: candidate,
        manifest: CloudAwardLocalIndexManifest(
          periodId: '115-05-06',
          tierCode: 'cloud-500',
          officialSourceUri: Uri.parse(
            'https://invoice.etax.nat.gov.tw/pdf/legacy_sorted_AI_D.pdf'),
          pdfSha256: 'a' * 64,
          indexSha256: 'b' * 64,
          extractorVersion: 'release-witness',
          rowCount: 1,
          builtAt: DateTime.utc(2026, 11, 6),
        ),
      ),
    ));
    _require(rootCalls == 0 && _sameBytes(
        await candidate.readAsBytes(), originalCandidate),
        'CLOUD500_LKG_OR_CANDIDATE_MUTATED');

    // Real Android preference/SQLite file snapshots, on a disposable emulator.
    final prefs = await SharedPreferences.getInstance();
    const receiptKey = 'issue13_remittance_observations_v1';
    final beforeReceipt = prefs.getString(receiptKey);
    final beforeDatabases = await _databaseFiles();
    final proposal = InvoiceAwardPayoutBookkeepingProposal(
      invoiceIdentity: 'synthetic-release-witness',
      awardPeriodId: '115-05-06',
      prizeTier: 'cloud-500',
      grossAmount: 500,
      localAccountId: 'synthetic-bank',
      externalRemittanceEligibleAt: DateTime.utc(2026, 8, 5, 16),
      officialDatasetFingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      parserRuleVersion: 'release-witness',
    );
    final receipt = InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 7),
      confirmedAtUtc: DateTime.utc(2026, 10, 8),
    );
    await _expectDeferred(() =>
        InvoiceAwardRemittanceReceiptRepository(prefs).confirmObservedCredit(
          proposal: proposal,
          receivedAtUtc: DateTime.utc(2026, 10, 7),
          confirmedAtUtc: DateTime.utc(2026, 10, 8),
        ));
    await _expectDeferred(() =>
        const InvoiceAwardFormalIncomePostingService().post(
          proposal: proposal,
          receipt: receipt,
          authorizedAtUtc: DateTime.utc(2026, 10, 9),
        ));
    _require(prefs.getString(receiptKey) == beforeReceipt,
        'CLOUD500_PREFERENCES_MUTATED');
    _require(_sameFiles(await _databaseFiles(), beforeDatabases),
        'CLOUD500_SQLITE_FILES_MUTATED');

    // This bounded runtime witness is NOT full C13/C17/C18 or Owner UAT.
    debugPrint('C500_RELEASE_WITNESS_PASS release=true ui=3 lkg=2 '
        'receipt_blocked=true posting_blocked=true '
        'preferences_unchanged=true sqlite_files_unchanged=true');
  } catch (error, stack) {
    debugPrint('C500_RELEASE_WITNESS_FAIL $error');
    debugPrint(stack.toString());
  } finally {
    if (sandbox != null && await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  }
}

InvoiceAwardMatchProjection _projection(
  int amount, String label, InvoiceAwardProjectionDomain domain,
) => InvoiceAwardMatchProjection(
  periodId: '115-05-06',
  domain: domain,
  tierLabel: label,
  grossAmount: amount,
  redemptionStart: DateTime.utc(2026, 10, 6),
  redemptionEnd: DateTime.utc(2027, 1, 5),
  officialDatasetFingerprint:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  parserRuleVersion: 'release-witness',
  eligibilityWarning: null,
  exclusionWarnings: const <String>[],
);

Future<void> _expectDeferred(Future<Object?> Function() action) async {
  try {
    await action();
  } on StateError catch (error) {
    if (error.toString().contains(Cloud500ProductionPolicy.deferredCode)) {
      return;
    }
    rethrow;
  }
  throw StateError('CLOUD500_UNEXPECTEDLY_AUTHORIZED');
}

Future<Map<String, int>> _databaseFiles() async {
  final root = Directory(await getDatabasesPath());
  if (!await root.exists()) return <String, int>{};
  final files = <String, int>{};
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    if (entry is File) files[entry.path] = await entry.length();
  }
  return files;
}

bool _sameFiles(Map<String, int> a, Map<String, int> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

bool _sameBytes(List<int> a, List<int> b) =>
    a.length == b.length &&
    List<int>.generate(a.length, (index) => index)
        .every((index) => a[index] == b[index]);

void _require(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}
