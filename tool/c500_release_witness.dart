// CI-only release-AOT entrypoint. Never bundled by production main().
 // No user data, official PDF download, production signing or formal DB writes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance_app/main.dart' show buildProductionApp;
import 'package:my_finance_app/routing/app_router.dart';
import 'package:my_finance_app/features/invoice/invoice_award_check_page.dart';
import 'package:my_finance_app/features/invoice/invoice_award_production_page.dart';
import 'package:my_finance_app/database/production_schema_v24.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/transaction/transaction_ledger_refresh_signal.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud500_production_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_award_check_presentation.dart';
import 'package:my_finance_app/features/invoice/invoice_award_match_projection.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_index_lkg_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_index.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_award_remittance_receipt_evidence.dart';
import 'package:my_finance_app/features/invoice/invoice_award_formal_income_posting_service.dart';
import 'package:my_finance_app/features/invoice/invoice_award_formal_posting_confirmation.dart';

import 'package:my_finance_app/database/production_database_coordinator.dart';
import 'package:my_finance_app/features/account/account_repository.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_candidate_repository.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_general_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_cloud_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';
import 'package:my_finance_app/features/invoice/invoice_award_period_catalog.dart';
import 'package:my_finance_app/features/invoice/invoice_award_payout_bookkeeping_runtime.dart';
import 'package:my_finance_app/features/invoice/invoice_award_running_task_bridge.dart';

const bool _fullPathWitnessEnabled =
    bool.fromEnvironment('C500_FULL_PATH_WITNESS', defaultValue: false);

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

    await _runV24LedgerWitness(sandboxDir, prefs);
    await _runProductionRouterWitness(prefs);

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

// Exercise the actual production ProviderScope -> MyFinanceApp -> GoRouter
// on a disposable API35 Release-AOT process. Consent is opened using the
// rendered production page context, not an alternate MaterialApp. This proves
// cancel/stale no-post paths only, not a positive Owner ledger E2E.
Future<void> _runProductionRouterWitness(SharedPreferences prefs) async {
  const receiptKey = 'issue13_remittance_observations_v1';
  const lkgKey = 'invoice_award.general_lkg.v1.115-05-06';
  final fixture = await _seedProductionButtonWitness(prefs);
  final receiptBefore = prefs.getString(receiptKey);
  final lkgBefore = prefs.getString(lkgKey);
  runApp(buildProductionApp());
  WidgetsBinding.instance.scheduleFrame();
  await WidgetsBinding.instance.endOfFrame;
  appRouter.go(InvoiceAwardCheckPage.routePath);
  WidgetsBinding.instance.scheduleFrame();
  await WidgetsBinding.instance.endOfFrame;
  WidgetsBinding.instance.scheduleFrame();
  await WidgetsBinding.instance.endOfFrame;

  BuildContext? awardContext;
  void inspect(Element element) {
    if (element.widget is InvoiceAwardProductionPage) {
      awardContext = element;
    }
    element.visitChildElements(inspect);
  }
  final root = WidgetsBinding.instance.rootElement;
  _require(root != null, 'PRODUCTION_ROUTER_ROOT_NOT_MOUNTED');
  inspect(root!);
  _require(awardContext != null && awardContext!.mounted,
      'PRODUCTION_AWARD_ROUTE_NOT_RENDERED');
  await _runProductionConsentNoWriteWitness(awardContext!, prefs);
  _require(prefs.getString(receiptKey) == receiptBefore &&
      prefs.getString(lkgKey) == lkgBefore,
      'PRODUCTION_ROUTE_RECEIPT_OR_LKG_MUTATED');
  debugPrint('C500_RELEASE_MAIN_ROUTER_PASS '
      'root=production provider_scope=true award_route_rendered=true '
      'receipt_unchanged=true lkg_unchanged=true owner_data=false');
  await _runProductionButtonV24Witness(fixture, prefs);
}

// This uses the same production confirmation implementation on the real
// production route. Neither cancel nor stale consent may invoke the posting
// service, mutate receipt/LKG or alter the disposable emulator DB file set.
// A positive NT$200 service/SQLite path is verified separately by the V24
// witness. This does NOT claim the production page's readiness was seeded.
Future<void> _runProductionConsentNoWriteWitness(
    BuildContext awardContext, SharedPreferences prefs) async {
  const receiptKey = 'issue13_remittance_observations_v1';
  const lkgKey = 'invoice_award.general_lkg.v1.115-05-06';
  final receiptBefore = prefs.getString(receiptKey);
  final lkgBefore = prefs.getString(lkgKey);
  // Let normal route initialization finish before taking the no-write baseline.
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final databasesBefore = await _databaseFiles();
  const flow = InvoiceAwardFormalPostingConfirmation();
  final general = _v24Proposal('router-consent-general-200',
      'general-sixth', 200);
  final generalReceipt = _v24Receipt(general);
  var postingStarted = 0;

  final cancel = flow.requestAndPost(
    context: awardContext,
    proposal: general,
    receipt: generalReceipt,
    nowUtc: () => DateTime.utc(2026, 10, 9, 3),
    authorizationStillValid: () => true,
    onPostingStarted: () => postingStarted++,
  );
  await _tapProductionDialogAction('取消');
  _require(await cancel == null && postingStarted == 0,
      'PRODUCTION_CANCEL_INVOKED_POSTING');
  // Wait for the outgoing dialog transition before opening the next one.
  await Future<void>.delayed(const Duration(milliseconds: 350));

  var stillAuthorized = true;
  final stale = flow.requestAndPost(
    context: awardContext,
    proposal: general,
    receipt: generalReceipt,
    nowUtc: () => DateTime.utc(2026, 10, 9, 3),
    authorizationStillValid: () => stillAuthorized,
    onPostingStarted: () => postingStarted++,
  ).then<Object?>((value) => value, onError: (Object error) => error);
  await _tapProductionDialogAction(
    '確認新增正式收入',
    beforeTap: () => stillAuthorized = false,
  );
  final staleResult = await stale;
  _require(staleResult is StateError &&
      staleResult.toString().contains(
          'INVOICE_AWARD_POSTING_UI_AUTHORITY_STALE') &&
      postingStarted == 0,
      'PRODUCTION_STALE_CONSENT_INVOKED_POSTING');
  await Future<void>.delayed(const Duration(milliseconds: 350));

  final deferred = _v24Proposal(
      'router-consent-cloud500', 'cloud-500', 500);
  await _expectDeferred(() => flow.requestAndPost(
    context: awardContext,
    proposal: deferred,
    receipt: _v24Receipt(deferred),
    nowUtc: () => DateTime.utc(2026, 10, 9, 3),
    authorizationStillValid: () => true,
    onPostingStarted: () => postingStarted++,
  ));
  _require(postingStarted == 0, 'PRODUCTION_DEFERRED_INVOKED_POSTING');
  _require(prefs.getString(receiptKey) == receiptBefore &&
      prefs.getString(lkgKey) == lkgBefore,
      'PRODUCTION_CONSENT_RECEIPT_OR_LKG_MUTATED');
  _require(_sameFiles(await _databaseFiles(), databasesBefore),
      'PRODUCTION_CONSENT_SQLITE_FILE_SET_MUTATED');
  debugPrint('C500_RELEASE_MAIN_CONSENT_NO_WRITE_PASS '
      'root=production modal=real cancel=true stale=true '
      'cloud500_deferred=true posting_started=0 '
      'receipt_lkg_unchanged=true sqlite_file_lengths_unchanged=true '
      'owner_data=false');
}


class _ProductionButtonFixture {
  const _ProductionButtonFixture(this.db, this.stale, this.positive,
      this.historical, this.cloudIdentity);
  final Database db;
  final InvoiceAwardPayoutBookkeepingProposal stale;
  final InvoiceAwardPayoutBookkeepingProposal positive;
  final String historical;
  final String cloudIdentity;
}

// No product injection seam: only the separate tool/ CI entrypoint can seed
// this synthetic, disposable emulator fixture. It is NOT MOF evidence or
// an Owner installation. The page and posting service remain unmodified.
Future<_ProductionButtonFixture> _seedProductionButtonWitness(
    SharedPreferences prefs) async {
  _require(_fullPathWitnessEnabled, 'FULL_PATH_COMPILE_GATE_MISSING');
  final db = await ProductionDatabaseCoordinator.instance.database;
  _require((await db.rawQuery('PRAGMA user_version')).single.values.first ==
      canonicalProductionSchemaVersion, 'FULL_PATH_SCHEMA_NOT_V24');
  _require((await db.query('transactions')).isEmpty,
      'FULL_PATH_NOT_A_FRESH_DISPOSABLE_DATABASE');
  final banks = (await AccountRepository.instance.listAccounts())
      .where((a) => a.type == AccountType.bank && !a.isArchived &&
          a.currency == CurrencyCode.twd).toList(growable: false);
  _require(banks.length == 1, 'FULL_PATH_BANK_NOT_UNIQUE');
  final settings = InvoiceAwardPayoutBookkeepingSettings(
      automaticBookkeepingEnabled: true,
      externalMofRemittanceConfigured: true,
      localAccountId: banks.single.id);
  await InvoiceAwardPayoutBookkeepingSettingsRepository(prefs).save(settings);
  final now = DateTime.now().toUtc();
  final period = InvoiceAwardRecentPeriodCatalog.defaultAt(now.toLocal());
  _require(period.isRedeemableAt(now.toLocal()),
      'FULL_PATH_PERIOD_NOT_REDEEMABLE');
  final invoiceDate = DateTime.utc(
      period.period.rocYear + 1911, period.period.startMonth, 7);
  ExistingInvoiceAwardCandidate candidate(String id, String number,
          ExistingInvoiceAwardIdentitySource source) =>
      ExistingInvoiceAwardCandidate(
        transactionId: id, invoiceNumber: number,
        invoiceDate: invoiceDate,
        awardPeriod: period.candidateAwardPeriodLabel,
        identitySource: source,
        sourceProvenance: 'disposable-release-fixture',
        cloudEligibility: source == ExistingInvoiceAwardIdentitySource.cloudMetadata
            ? ExistingInvoiceAwardCloudEligibility.unknownReviewRequired
            : ExistingInvoiceAwardCloudEligibility.ineligible);
  final negative = candidate('release-negative', 'AB12345678',
      ExistingInvoiceAwardIdentitySource.governedReviewNote);
  final positive = candidate('release-positive', 'CD12345678',
      ExistingInvoiceAwardIdentitySource.governedReviewNote);
  final cloud = candidate('release-cloud500', 'EF87654321',
      ExistingInvoiceAwardIdentitySource.cloudMetadata);
  final dataset = OfficialInvoiceAwardDataset(
      period: period.period,
      provenance: OfficialInvoiceAwardProvenance(
          sourceId: OfficialInvoiceAwardProvenance.ministryOfFinanceSourceId,
          fetchedAt: now, parserVersion: 'disposable-release-fixture',
          contentSha256: 'a' * 64),
      rules: const <OfficialInvoiceAwardRule>[
        OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.special, number: '11111111'),
        OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.grand, number: '22222222'),
        OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.first, number: '99999678'),
      ],
      published: true, complete: true);
  _require(const OfficialInvoiceAwardDatasetValidator().validate(dataset).isValid,
      'FULL_PATH_GENERAL_FIXTURE_INVALID');
  final general = const ExistingInvoiceAwardGeneralBatchMatcher().evaluate(
      dataset: dataset, candidates: <ExistingInvoiceAwardCandidate>[
        negative, positive,
      ]);
  _require(general.length == 2 && general.every((e) =>
      e.isWinner && e.grossAmount == 200 &&
      e.matchKind == OfficialInvoiceAwardMatchKind.sixth),
      'FULL_PATH_GENERAL_SIXTH_NOT_READY');
  final cloudEvaluation = ExistingInvoiceAwardCloudEvaluation(
      candidate: cloud,
      status: ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired,
      missingTierCodes: const <String>{},
      matchedTierCodes: const <String>{'cloud-500'},
      selectedTierCode: 'cloud-500', grossAmount: 500, pdfSha256: 'b' * 64);
  final cloudRows = <ExistingInvoiceAwardCloudEvaluation>[cloudEvaluation];
  final readiness = const InvoiceAwardPayoutBookkeepingPlanner().evaluate(
      period: period, nowUtc: now, settings: settings,
      generalAuthorityComplete: true, cloudAuthorityComplete: false,
      generalDataset: dataset, generalEvaluations: general,
      cloudEvaluations: cloudRows,
      cloudEligibilityConfirmations: const {});
  final ready = readiness.where((r) => r.isReady).toList();
  _require(ready.length == 2 &&
      readiness.any((r) => r.prizeTier == 'cloud-500' && !r.isReady),
      'FULL_PATH_READINESS_NOT_FAIL_CLOSED');
  final stale = ready.singleWhere((r) =>
      r.invoiceIdentity == negative.dedupeKey).proposal!;
  final good = ready.singleWhere((r) =>
      r.invoiceIdentity == positive.dedupeKey).proposal!;
  final receipts = InvoiceAwardRemittanceReceiptRepository(prefs);
  for (final proposal in <InvoiceAwardPayoutBookkeepingProposal>[stale, good]) {
    await receipts.confirmObservedCredit(
        proposal: proposal,
        receivedAtUtc: now.subtract(const Duration(hours: 2)),
        confirmedAtUtc: now.subtract(const Duration(hours: 1)));
  }
  for (final amount in <int>[500, 700]) {
    await db.insert('transactions',
        _v24HistoricalRecord('release-root-history-$amount',
            amount.toDouble()).toMap());
  }
  final historical = jsonEncode(await db.query('transactions',
      where: 'id IN (?, ?)',
      whereArgs: const <Object>['release-root-history-500',
          'release-root-history-700'], orderBy: 'id'));
  final bridge = InvoiceAwardRunningTaskBridge.shared;
  _require(bridge.begin(period.period.id), 'FULL_PATH_BRIDGE_BUSY');
  final generation = bridge.generation;
  bridge.publish(generation, InvoiceAwardRunningTaskSnapshot(
      periodId: period.period.id,
      status: 'Synthetic fixture, not official MOF evidence',
      cloudStatus: 'Cloud-500 UNKNOWN/deferred',
      scanStatus: 'Disposable release fixture',
      generalDataset: dataset,
      candidates: <ExistingInvoiceAwardCandidate>[negative, positive, cloud],
      generalEvaluations: general, cloudEvaluations: cloudRows));
  bridge.finish(generation, period.period.id);
  return _ProductionButtonFixture(db, stale, good, historical, cloud.dedupeKey);
}

// This invokes the callback on the actual rendered InvoiceAwardProductionPage
// FilledButton, not a manually constructed modal or test posting service.
Future<void> _pressProductionPostingButton(String identity) async {
  final key = ValueKey<String>('invoice_award_formal_post_$identity');
  for (var i = 0; i < 30; i++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    VoidCallback? callback;
    void find(Element element) {
      final widget = element.widget;
      if (widget is FilledButton && widget.key == key) {
        callback = widget.onPressed;
      }
      element.visitChildElements(find);
    }
    final root = WidgetsBinding.instance.rootElement;
    if (root != null) find(root);
    if (callback != null) {
      callback!();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('FULL_PATH_OWN_FILLED_BUTTON_NOT_RENDERED');
}

Future<void> _runProductionButtonV24Witness(
    _ProductionButtonFixture fixture, SharedPreferences prefs) async {
  final db = fixture.db;
  final receiptRepo = InvoiceAwardRemittanceReceiptRepository(prefs);
  final lkgBefore = prefs.getString('invoice_award.general_lkg.v1.115-07-08');
  final signals = <int>[];
  final sub = TransactionLedgerRefreshSignal.instance.stream
      .listen((_) => signals.add(1));
  try {
    var cloudButton = false;
    final cloudKey = ValueKey<String>(
        'invoice_award_formal_post_${fixture.cloudIdentity}');
    void inspect(Element element) {
      if (element.widget is FilledButton && element.widget.key == cloudKey) {
        cloudButton = true;
      }
      element.visitChildElements(inspect);
    }
    final root = WidgetsBinding.instance.rootElement;
    _require(root != null, 'FULL_PATH_ROOT_MISSING');
    inspect(root!);
    _require(!cloudButton, 'FULL_PATH_CLOUD500_BUTTON_VISIBLE');
    final before = jsonEncode(await db.query('transactions', orderBy: 'id'));
    final beforeChanges = (await db.rawQuery(
        'SELECT total_changes() AS n')).single['n'];
    await _pressProductionPostingButton(fixture.stale.invoiceIdentity);
    await _tapProductionDialogAction('取消');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _require(jsonEncode(await db.query('transactions', orderBy: 'id')) ==
        before && (await db.rawQuery(
        'SELECT total_changes() AS n')).single['n'] == beforeChanges &&
        signals.isEmpty, 'FULL_PATH_CANCEL_WROTE_LEDGER');
    final oldObservation = receiptRepo.readForProposal(fixture.stale)!;
    _require(oldObservation.observationRevision != null,
        'FULL_PATH_INITIAL_RECEIPT_REVISION_MISSING');
    await _pressProductionPostingButton(fixture.stale.invoiceIdentity);
    await receiptRepo.revokeForProposal(fixture.stale);
    // Same timestamps, different durable revision: stale consent must
    // reject before any formal SQLite write.
    final renewed = await receiptRepo.confirmObservedCredit(
      proposal: fixture.stale,
      receivedAtUtc: oldObservation.receivedAtUtc,
      confirmedAtUtc: oldObservation.confirmedAtUtc,
    );
    _require(!oldObservation.sameObservationAs(renewed),
        'FULL_PATH_RECONFIRM_REVISION_REUSED');
    await _tapProductionDialogAction('確認新增正式收入');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _require(jsonEncode(await db.query('transactions', orderBy: 'id')) ==
        before && (await db.rawQuery(
        'SELECT total_changes() AS n')).single['n'] == beforeChanges &&
        signals.isEmpty, 'FULL_PATH_STALE_WROTE_LEDGER');
    final receiptAfterReconfirmation =
        prefs.getString('issue13_remittance_observations_v1');
    await _pressProductionPostingButton(fixture.positive.invoiceIdentity);
    await _tapProductionDialogAction('確認新增正式收入');
    final postedId = InvoiceAwardFormalIncomePostingService.stableRecordId(
        fixture.positive);
    var posted = false;
    for (var i = 0; i < 30; i++) {
      if ((await db.query('transactions', where: 'id = ?',
          whereArgs: <Object>[postedId])).length == 1) {
        posted = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _require(posted, 'FULL_PATH_GENERAL_200_NOT_POSTED');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _require(signals.length == 1, 'FULL_PATH_PROVIDER_NOT_ONCE');
    _require(jsonEncode(await db.query('transactions',
        where: 'id IN (?, ?)',
        whereArgs: const <Object>['release-root-history-500',
            'release-root-history-700'], orderBy: 'id')) ==
        fixture.historical, 'FULL_PATH_HISTORY_CHANGED');
    _require(prefs.getString('invoice_award.general_lkg.v1.115-07-08') ==
        lkgBefore &&
        prefs.getString('issue13_remittance_observations_v1') ==
        receiptAfterReconfirmation, 'FULL_PATH_PREFS_CHANGED_BY_POST');
    _require(!await const InvoiceAwardFormalIncomePostingService().post(
        proposal: fixture.positive,
        receipt: receiptRepo.readForProposal(fixture.positive)!,
        authorizedAtUtc: DateTime.now().toUtc()),
        'FULL_PATH_DUPLICATE_POSTED');
    _require(signals.length == 1, 'FULL_PATH_DUPLICATE_PROVIDER_REFRESH');
    _require((await db.rawQuery('PRAGMA foreign_key_check')).isEmpty,
        'FULL_PATH_V24_FK_FAILURE');
    debugPrint('C500_RELEASE_PRODUCTION_BUTTON_V24_PASS '
        'root=production own_filled_button_callback=true '
        'consent=explicit durable_receipt_revision=true '
        'schema=24 cancel_stale_same_timestamp_reconfirm_zero_write=true cloud500_no_button=true '
        'general_200_once=true provider_new_only=true '
        'historical_500_700_unchanged=true lkg_unchanged=true '
        'synthetic_official_fixture=true owner_data=false');
  } finally {
    await sub.cancel();
  }
}

// Invoke a real production Navigator dialog button via its rendered widget.
// Bounded frame search fails closed rather than silently bypassing consent.
Future<void> _tapProductionDialogAction(
    String label, {void Function()? beforeTap}) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    VoidCallback? action;
    void find(Element element) {
      final widget = element.widget;
      if (widget is ButtonStyleButton &&
          widget.child is Text &&
          (widget.child as Text).data == label) {
        action = widget.onPressed;
      }
      element.visitChildElements(find);
    }
    final root = WidgetsBinding.instance.rootElement;
    if (root != null) find(root);
    if (action != null) {
      beforeTap?.call();
      action!();
      return;
    }
  }
  throw StateError('PRODUCTION_CONSENT_BUTTON_NOT_RENDERED_$label');
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

 
// Runs inside an actual release-AOT APK on API35. This is a disposable,
// isolated Android SQLite file with the canonical V24 extension, NOT the
// installed user's database or the production main()/UI/Provider route.
// Fail closed on every negative path before claiming the separate V24 marker.
Future<void> _runV24LedgerWitness(
    Directory sandboxDir, SharedPreferences prefs) async {
  final db = await openDatabase(
    '${sandboxDir.path}/release-v24-witness.sqlite',
    singleInstance: false,
    version: canonicalProductionSchemaVersion,
    onConfigure: (database) async {
      await database.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (database, _) async {
      await database.execute('''
        CREATE TABLE transactions (
          id TEXT PRIMARY KEY, type TEXT NOT NULL,
          amount REAL NOT NULL, category TEXT NOT NULL,
          occurred_at TEXT NOT NULL, account_name TEXT NOT NULL,
          member_name TEXT NOT NULL, merchant_name TEXT NOT NULL,
          tag_name TEXT NOT NULL, note TEXT NOT NULL,
          currency_code TEXT NOT NULL DEFAULT 'TWD',
          exchange_rate_to_base REAL NOT NULL DEFAULT 1,
          base_amount REAL NOT NULL DEFAULT 0,
          from_account_name TEXT, to_account_name TEXT,
          repayment_group_id TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await database.execute('''
        CREATE TABLE accounts (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
          is_archived INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await createCanonicalProductionV24Tables(database);
    },
  );
  final signals = <int>[];
  final subscription = TransactionLedgerRefreshSignal.instance.stream
      .listen((_) => signals.add(1));
  try {
    await db.insert('accounts', <String, Object?>{
      'id': 'release-bank', 'name': 'Release witness bank', 'type': 'bank',
    });
    await db.insert('business_registry_snapshots', <String, Object?>{
      'version': 'release-v24-registry',
      'source_dataset': 'synthetic-release-only',
      'content_sha256': 'b' * 64,
      'status': 'installed',
      'created_at': '2026-11-07T00:00:00Z',
    });
    await db.insert('business_registry_official_details', <String, Object?>{
      'snapshot_version': 'release-v24-registry',
      'jurisdiction': 'TW',
      'seller_identifier': '12345678',
      'official_json': '{"release":"preserve"}',
    });
    final scope = await FullBackupScope.inspect(db);
    _require(scope.isComplete &&
        scope.excludedPresentTables.contains('business_registry_official_details'),
        'V24_BACKUP_SCOPE_INCOMPLETE');
    // The disposable release-AOT test harness intentionally injects only
    // synthetic accounts and its isolated V24 SQLite file.
    // ignore: invalid_use_of_visible_for_testing_member
    final service = InvoiceAwardFormalIncomePostingService.forIsolatedTest(
      databaseProvider: () async => db,
      accountsProvider: () async => <AccountRecord>[
        const AccountRecord(
          id: 'release-bank', name: 'Release witness bank',
          type: AccountType.bank, initialBalance: 0, sortOrder: 0,
        ),
      ],
    );
    final historical = _v24Proposal('historical-500', 'cloud-500', 500);
    final historicalId =
        InvoiceAwardFormalIncomePostingService.stableRecordId(historical);
    await db.insert('transactions',
        _v24HistoricalRecord(historicalId, 500).toMap());
    await db.insert('transactions',
        _v24HistoricalRecord('protected-nt700', 700).toMap());
    final rowsBefore = jsonEncode(await db.query('transactions', orderBy: 'id'));
    final backupBefore = jsonEncode((await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'release-v24'))['data']);
    const receiptKey = 'issue13_remittance_observations_v1';
    const lkgKey = 'invoice_award.general_lkg.v1.115-05-06';
    final receiptBefore = prefs.getString(receiptKey);
    final lkgBefore = prefs.getString(lkgKey);
    _require((await service.readPostedIds(<InvoiceAwardPayoutBookkeepingProposal>[
      historical,
    ])).contains(historicalId), 'V24_HISTORICAL_POSTED_MISSING');
    _require(signals.isEmpty, 'V24_UNEXPECTED_PROVIDER_SIGNAL');

    for (final tier in <String>[
      'cloud-500', ' CLOUD-500 ', 'cloud-0500', 'cloud500', 'cloud-800',
    ]) {
      final blocked = _v24Proposal('blocked-${tier.trim()}', tier, 500);
      final changesBefore =
          (await db.rawQuery('SELECT total_changes() AS n')).single['n'];
      await _expectDeferred(() =>
          InvoiceAwardRemittanceReceiptRepository(prefs).confirmObservedCredit(
            proposal: blocked,
            receivedAtUtc: DateTime.utc(2026, 10, 9),
            confirmedAtUtc: DateTime.utc(2026, 10, 9, 1),
          ));
      await _expectDeferred(() => service.post(
            proposal: blocked,
            receipt: _v24Receipt(blocked),
            authorizedAtUtc: DateTime.utc(2026, 10, 9, 3),
          ));
      _require(
          (await db.rawQuery('SELECT total_changes() AS n')).single['n'] ==
              changesBefore &&
          jsonEncode(await db.query('transactions', orderBy: 'id')) ==
              rowsBefore &&
          prefs.getString(receiptKey) == receiptBefore &&
          prefs.getString(lkgKey) == lkgBefore &&
          signals.isEmpty,
          'V24_CLOUD500_NO_WRITE_VIOLATION_${tier.trim()}');
    }
    _require(jsonEncode((await const FullBackupService()
        .buildFullBackupEnvelope(db, sourcePlatform: 'release-v24'))['data']) ==
        backupBefore, 'V24_CLOUD500_BACKUP_MUTATED');

    final general = _v24Proposal('general-200', 'general-sixth', 200);
    // A direct service call without a persisted manual receipt must fail
    // before SQLite, even on the disposable Release-AOT witness.
    var unconfirmedRejected = false;
    try {
      await service.post(
        proposal: general,
        receipt: _v24Receipt(general),
        authorizedAtUtc: DateTime.utc(2026, 10, 9, 3),
      );
    } on StateError catch (error) {
      unconfirmedRejected = error.toString().contains(
          'INVOICE_AWARD_POSTING_RECEIPT_NOT_CURRENT');
    }
    _require(unconfirmedRejected &&
        jsonEncode(await db.query('transactions', orderBy: 'id')) ==
            rowsBefore && signals.isEmpty,
        'V24_UNCONFIRMED_DIRECT_POST_NOT_REJECTED');
    final generalReceipt =
        await InvoiceAwardRemittanceReceiptRepository(prefs)
            .confirmObservedCredit(
      proposal: general,
      receivedAtUtc: DateTime.utc(2026, 10, 9),
      confirmedAtUtc: DateTime.utc(2026, 10, 9, 1),
    );
    final receiptAfterGeneral = prefs.getString(receiptKey);
    _require(await service.post(
      proposal: general,
      receipt: generalReceipt,
      authorizedAtUtc: DateTime.utc(2026, 10, 9, 3),
    ), 'V24_GENERAL_POST_REJECTED');
    _require(signals.length == 1, 'V24_PROVIDER_MISSING_NEW_INSERT');
    _require(!await service.post(
      proposal: general,
      receipt: generalReceipt,
      authorizedAtUtc: DateTime.utc(2026, 10, 9, 3),
    ), 'V24_DUPLICATE_INSERTED');
    _require(signals.length == 1, 'V24_DUPLICATE_PROVIDER_REFRESH');
    final generalId =
        InvoiceAwardFormalIncomePostingService.stableRecordId(general);
    _require((await db.query('transactions',
        where: 'id = ?', whereArgs: <Object>[generalId])).length == 1,
        'V24_GENERAL_LEDGER_MISSING');
    _require((await db.query('transactions',
        where: 'id IN (?, ?)',
        whereArgs: <Object>[historicalId, 'protected-nt700'])).length == 2,
        'V24_HISTORICAL_LEDGER_LOST');
    _require((await db.query('business_registry_official_details')).single
        ['official_json'] == '{"release":"preserve"}',
        'V24_REGISTRY_CACHE_MUTATED');
    _require((await db.rawQuery('PRAGMA foreign_key_check')).isEmpty,
        'V24_FOREIGN_KEY_BROKEN');
    _require(prefs.getString(receiptKey) == receiptAfterGeneral &&
        prefs.getString(lkgKey) == lkgBefore,
        'V24_PREFERENCES_OR_LKG_MUTATED');
    debugPrint('C500_RELEASE_V24_LEDGER_PASS schema=24 '
        'sqlite_android=true historical_500_700_preserved=true '
        'cloud500_no_write=true general_200_post_once=true '
        'provider_new_only=true lkg_unchanged=true');
  } finally {
    await subscription.cancel();
    await db.close();
  }
}

InvoiceAwardPayoutBookkeepingProposal _v24Proposal(
    String invoice, String tier, int amount) =>
    InvoiceAwardPayoutBookkeepingProposal(
      invoiceIdentity: invoice,
      awardPeriodId: '115-05-06',
      prizeTier: tier,
      grossAmount: amount,
      localAccountId: 'release-bank',
      externalRemittanceEligibleAt: DateTime.utc(2026, 8, 5, 16),
      officialDatasetFingerprint: 'a' * 64,
      parserRuleVersion: 'release-v24',
    );

InvoiceAwardRemittanceReceiptEvidence _v24Receipt(
    InvoiceAwardPayoutBookkeepingProposal proposal) =>
    InvoiceAwardRemittanceReceiptEvidence(
      proposalKey: proposal.idempotencyKey,
      awardPeriodId: proposal.awardPeriodId,
      localAccountId: proposal.localAccountId,
      prizeTier: proposal.prizeTier,
      grossAmount: proposal.grossAmount,
      officialFingerprint: proposal.officialDatasetFingerprint,
      receivedAtUtc: DateTime.utc(2026, 10, 9),
      confirmedAtUtc: DateTime.utc(2026, 10, 9, 1),
    );

TransactionRecord _v24HistoricalRecord(String id, double amount) =>
    TransactionRecord(
      id: id,
      type: TransactionType.income,
      amount: amount,
      category: '發票兌獎',
      occurredAt: DateTime.utc(2026, 10, 9),
      accountName: 'Release witness bank',
      memberName: '自己',
      merchantName: '',
      tagName: '',
      note: 'historical release V24 ledger sentinel',
      currency: CurrencyCode.twd,
    );
