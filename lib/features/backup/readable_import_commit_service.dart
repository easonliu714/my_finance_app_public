import 'package:sqflite/sqflite.dart';

import 'import_mapping_analysis_service.dart';
import 'import_mapping_decision_service.dart';
import 'readable_import_service.dart';

class ReadableImportCommitService {
  const ReadableImportCommitService({this.decisionService = const ImportMappingDecisionService(), this.importService = const ReadableImportService()});

  final ImportMappingDecisionService decisionService;
  final ReadableImportService importService;

  Future<ReadableImportCommitResult> commitReviewedTransactions(
    DatabaseExecutor db, {
    required ReadableImportDryRunResult dryRunResult,
    required ImportMappingAnalysisResult mappingAnalysis,
    required ImportMappingDecisionSet decisions,
    required bool confirmed,
  }) async {
    if (!confirmed) throw const ReadableImportException('尚未確認匯入，拒絕寫入正式資料');

    if (dryRunResult.readyToInsertRows <= 0) {
      return ReadableImportCommitResult(
        insertedRows: 0,
        skippedRows: dryRunResult.rows.length,
        duplicateAtCommitRows: 0,
        failedRows: 0,
        invalidRows: dryRunResult.invalidRows,
        failures: const <ReadableImportCommitFailure>[],
        blockingIssues: const <String>[],
      );
    }

    final validation = decisionService.validate(analysis: mappingAnalysis, decisions: decisions);
    if (!validation.canCommit) {
      return ReadableImportCommitResult(
        insertedRows: 0,
        skippedRows: dryRunResult.rows.length,
        duplicateAtCommitRows: 0,
        failedRows: 0,
        invalidRows: dryRunResult.invalidRows,
        failures: const <ReadableImportCommitFailure>[],
        blockingIssues: validation.blockingIssues.map((issue) => issue.message).toList(),
      );
    }

    final mappedDryRun = decisionService.previewApplyDecisions(dryRunResult, decisions);
    final result = await importService.commitReadyTransactions(db, mappedDryRun, confirmed: true);
    return result.copyWith(
      invalidRows: dryRunResult.invalidRows,
      blockingIssues: const <String>[],
    );
  }
}
