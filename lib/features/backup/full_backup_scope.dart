import 'package:sqflite/sqflite.dart';

import '../../database/production_schema_v22.dart';

class FullBackupScope {
  const FullBackupScope._();

  static const int exportFormatVersion = 2;
  static const int backupScopeVersion = 8;
  static const int databaseSchemaVersion = canonicalProductionSchemaVersion;

  static const Set<int> supportedExportFormatVersions = <int>{1, 2};
  static const Set<int> supportedBackupScopeVersions = <int>{
    2,
    3,
    4,
    5,
    6,
    7,
    8,
  };

  static const List<String> requiredTableNames = <String>[
    'accounts',
    'transactions',
  ];

  static const List<String> legacyScopeV2TableNames = <String>[
    'accounts',
    'merchants',
    'account_events',
    'transactions',
    'credit_card_statement_events',
    'credit_card_bank_rule_profiles',
    'credit_card_bank_rule_assignments',
    'credit_card_installment_plans',
    'credit_card_installment_schedule_items',
    'cloud_invoice_drafts',
    'cloud_invoice_metadata_links',
    'cloud_invoice_operations',
    'cloud_invoice_before_images',
    'cloud_invoice_audits',
    'cloud_invoice_draft_promotions',
    'cloud_invoice_detail_enrichments',
  ];

  static const List<String> legacyScopeV3TableNames = <String>[
    ...legacyScopeV2TableNames,
    'debit_card_profiles',
    'debit_card_settlements',
  ];

  static const List<String> legacyScopeV4TableNames = <String>[
    ...legacyScopeV3TableNames,
    'debit_card_authorization_audits',
  ];

  static const List<String> legacyScopeV5TableNames = <String>[
    ...legacyScopeV4TableNames,
    'debit_card_settlement_confirmation_audits',
  ];

  static const List<String> legacyScopeV6TableNames = <String>[
    ...legacyScopeV5TableNames,
    'wallet_top_up_profiles',
    'wallet_top_up_suggestions',
    'wallet_top_up_audits',
  ];

  static const List<String> legacyScopeV7TableNames = <String>[
    ...legacyScopeV6TableNames,
    'wallet_top_up_executions',
  ];

  /// User-owned merchant identity/history belongs in complete backups.
  /// Official registry cache is deliberately excluded because it is
  /// replaceable/redownloadable public reference data.
  static const List<String> merchantIdentityUserTableNames = <String>[
    'merchant_brands',
    'merchant_brand_aliases',
    'merchant_legal_entities',
    'merchant_branches_or_outlets',
    'merchant_brand_legal_links',
    'merchant_identity_observations',
  ];

  static const List<String> backupTableNames = <String>[
    ...legacyScopeV7TableNames,
    ...merchantIdentityUserTableNames,
  ];

  static const Set<String> scopeV3OptionalForLegacyRestore = <String>{
    'debit_card_profiles',
    'debit_card_settlements',
  };

  static const Set<String> scopeV4OptionalForLegacyRestore = <String>{
    'debit_card_authorization_audits',
  };

  static const Set<String> scopeV5OptionalForLegacyRestore = <String>{
    'debit_card_settlement_confirmation_audits',
  };

  static const Set<String> scopeV6OptionalForLegacyRestore = <String>{
    'wallet_top_up_profiles',
    'wallet_top_up_suggestions',
    'wallet_top_up_audits',
  };

  static const Set<String> scopeV7OptionalForLegacyRestore = <String>{
    'wallet_top_up_executions',
  };

  static const Set<String> scopeV8OptionalForLegacyRestore = <String>{
    ...merchantIdentityUserTableNames,
  };

  static const Set<String> explicitlyExcludedTableNames = <String>{
    'production_migration_markers',
    'app_settings',
    'android_metadata',
    'taiwan_business_calendar_days',
    'business_registry_snapshots',
    'business_registry_entities',
    'business_registry_negative_lookups',
  };

  static Future<FullBackupCoverageReport> inspect(
    DatabaseExecutor db,
  ) async {
    final rows = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
      ORDER BY name ASC
    ''');
    final presentTables = rows
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    final approvedTables = backupTableNames.toSet();

    final includedPresent = presentTables.intersection(approvedTables).toList()
      ..sort();
    final excludedPresent = presentTables
        .intersection(explicitlyExcludedTableNames)
        .toList()
      ..sort();
    final unknownTables = presentTables
        .difference(approvedTables)
        .difference(explicitlyExcludedTableNames)
        .toList()
      ..sort();
    final missingRequired = requiredTableNames
        .where((tableName) => !presentTables.contains(tableName))
        .toList()
      ..sort();
    final missingOptional = backupTableNames
        .where(
          (tableName) =>
              !presentTables.contains(tableName) &&
              !requiredTableNames.contains(tableName),
        )
        .toList()
      ..sort();

    return FullBackupCoverageReport(
      presentTables: List<String>.unmodifiable(presentTables.toList()..sort()),
      includedPresentTables: List<String>.unmodifiable(includedPresent),
      excludedPresentTables: List<String>.unmodifiable(excludedPresent),
      unknownTables: List<String>.unmodifiable(unknownTables),
      missingRequiredTables: List<String>.unmodifiable(missingRequired),
      missingOptionalTables: List<String>.unmodifiable(missingOptional),
    );
  }
}

class FullBackupCoverageReport {
  const FullBackupCoverageReport({
    required this.presentTables,
    required this.includedPresentTables,
    required this.excludedPresentTables,
    required this.unknownTables,
    required this.missingRequiredTables,
    required this.missingOptionalTables,
  });

  final List<String> presentTables;
  final List<String> includedPresentTables;
  final List<String> excludedPresentTables;
  final List<String> unknownTables;
  final List<String> missingRequiredTables;
  final List<String> missingOptionalTables;

  bool get isComplete =>
      unknownTables.isEmpty && missingRequiredTables.isEmpty;

  Map<String, Object?> toMetadata() => <String, Object?>{
        'backup_scope_version': FullBackupScope.backupScopeVersion,
        'included_tables': FullBackupScope.backupTableNames,
        'included_present_tables': includedPresentTables,
        'excluded_present_tables': excludedPresentTables,
        'missing_optional_tables': missingOptionalTables,
        'unknown_tables': unknownTables,
        'missing_required_tables': missingRequiredTables,
        'coverage_complete': isComplete,
      };

  String blockingMessage() {
    final details = <String>[];
    if (unknownTables.isNotEmpty) {
      details.add('未知資料表：${unknownTables.join(', ')}');
    }
    if (missingRequiredTables.isNotEmpty) {
      details.add('缺少必要資料表：${missingRequiredTables.join(', ')}');
    }
    return details.isEmpty ? '完整備份範圍驗證失敗' : details.join('；');
  }
}

class FullBackupCoverageException implements Exception {
  const FullBackupCoverageException(this.message);

  final String message;

  @override
  String toString() => message;
}
