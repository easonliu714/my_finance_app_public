import 'import_mapping_analysis_service.dart';
import 'readable_import_service.dart';

class ImportMappingDecisionService {
  const ImportMappingDecisionService();

  static const String appVersion = '3.4.5+138';
  static const String phase = 'P3.4.5';

  ImportMappingDecisionValidationResult validate({required ImportMappingAnalysisResult analysis, required ImportMappingDecisionSet decisions}) {
    final blockingIssues = <ImportMappingDecisionIssue>[];
    final unresolvedCategories = <String>[];
    final unresolvedMerchants = <String>[];

    for (final reference in analysis.accountReferences) {
      final decision = decisions.accountDecisionFor(fieldName: reference.fieldName, importedValue: reference.value);
      final needsDecision = reference.status == ImportAccountMappingStatus.missing || reference.status == ImportAccountMappingStatus.ambiguous;
      if (needsDecision && decision == null) {
        blockingIssues.add(ImportMappingDecisionIssue(kind: ImportMappingDecisionIssueKind.missingAccountDecision, fieldName: reference.fieldName, importedValue: reference.value, message: '帳戶對應尚未決定：${reference.fieldName} / ${reference.value}'));
      }
    }

    for (final category in analysis.categories) {
      if (decisions.categoryDecisionFor(category) == null) unresolvedCategories.add(category);
    }
    for (final merchant in analysis.merchants) {
      if (decisions.merchantDecisionFor(merchant) == null) unresolvedMerchants.add(merchant);
    }

    return ImportMappingDecisionValidationResult(blockingIssues: blockingIssues, unresolvedCategories: unresolvedCategories, unresolvedMerchants: unresolvedMerchants);
  }

  ReadableImportDryRunResult previewApplyDecisions(ReadableImportDryRunResult dryRunResult, ImportMappingDecisionSet decisions) {
    final rows = dryRunResult.rows.map((row) {
      final copiedRow = Map<String, Object?>.from(row.row);
      for (final decision in decisions.accountDecisions) {
        if ((copiedRow[decision.fieldName]?.toString().trim() ?? '') == decision.importedValue) {
          copiedRow[decision.fieldName] = decision.selectedDisplayName;
          copiedRow['${decision.fieldName}_mapped_account_id'] = decision.selectedAccountId;
        }
      }
      final category = copiedRow['category']?.toString().trim() ?? '';
      final categoryDecision = decisions.categoryDecisionFor(category);
      if (categoryDecision != null) copiedRow['category'] = categoryDecision.mappedCategory;

      final merchant = copiedRow['merchant_name']?.toString().trim() ?? '';
      final merchantDecision = decisions.merchantDecisionFor(merchant);
      if (merchantDecision != null) copiedRow['merchant_name'] = merchantDecision.mappedMerchant;

      return ReadableImportRowResult(sourceRowIndex: row.sourceRowIndex, row: copiedRow, status: row.status, errors: row.errors);
    }).toList();
    return ReadableImportDryRunResult(totalRows: dryRunResult.totalRows, validRows: dryRunResult.validRows, invalidRows: dryRunResult.invalidRows, duplicateRows: dryRunResult.duplicateRows, readyToInsertRows: dryRunResult.readyToInsertRows, rows: rows);
  }
}

class ImportMappingDecisionSet {
  const ImportMappingDecisionSet({this.accountDecisions = const <ImportAccountMappingDecision>[], this.categoryDecisions = const <ImportCategoryMappingDecision>[], this.merchantDecisions = const <ImportMerchantMappingDecision>[]});

  final List<ImportAccountMappingDecision> accountDecisions;
  final List<ImportCategoryMappingDecision> categoryDecisions;
  final List<ImportMerchantMappingDecision> merchantDecisions;

  ImportAccountMappingDecision? accountDecisionFor({required String fieldName, required String importedValue}) {
    for (final decision in accountDecisions) {
      if (decision.fieldName == fieldName && decision.importedValue == importedValue) return decision;
    }
    return null;
  }

  ImportCategoryMappingDecision? categoryDecisionFor(String importedCategory) {
    for (final decision in categoryDecisions) {
      if (decision.importedCategory == importedCategory) return decision;
    }
    return null;
  }

  ImportMerchantMappingDecision? merchantDecisionFor(String importedMerchant) {
    for (final decision in merchantDecisions) {
      if (decision.importedMerchant == importedMerchant) return decision;
    }
    return null;
  }
}

class ImportAccountMappingDecision {
  const ImportAccountMappingDecision({required this.fieldName, required this.importedValue, required this.selectedAccountId, required this.selectedDisplayName});

  final String fieldName;
  final String importedValue;
  final String selectedAccountId;
  final String selectedDisplayName;
}

class ImportCategoryMappingDecision {
  const ImportCategoryMappingDecision({required this.importedCategory, required this.mappedCategory});

  final String importedCategory;
  final String mappedCategory;
}

class ImportMerchantMappingDecision {
  const ImportMerchantMappingDecision({required this.importedMerchant, required this.mappedMerchant});

  final String importedMerchant;
  final String mappedMerchant;
}

class ImportMappingDecisionValidationResult {
  const ImportMappingDecisionValidationResult({required this.blockingIssues, required this.unresolvedCategories, required this.unresolvedMerchants});

  final List<ImportMappingDecisionIssue> blockingIssues;
  final List<String> unresolvedCategories;
  final List<String> unresolvedMerchants;
  bool get canCommit => blockingIssues.isEmpty;
}

class ImportMappingDecisionIssue {
  const ImportMappingDecisionIssue({required this.kind, required this.fieldName, required this.importedValue, required this.message});

  final ImportMappingDecisionIssueKind kind;
  final String fieldName;
  final String importedValue;
  final String message;
}

enum ImportMappingDecisionIssueKind { missingAccountDecision }
