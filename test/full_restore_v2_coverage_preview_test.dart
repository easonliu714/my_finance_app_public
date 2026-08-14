import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';
import 'package:my_finance_app/features/backup/full_backup_service.dart';
import 'package:my_finance_app/features/backup/full_restore_preview_service.dart';

void main() {
  test('valid Scope V6 coverage is previewable with V20 metadata', () async {
    final preview = await const FullRestorePreviewService().previewBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(_scopeV6Envelope()))),
      sourceUri: 'provider:v6-backup.json',
      fileName: 'v6-backup.json',
    );

    expect(preview.isValid, isTrue);
    expect(preview.message, contains('完整備份範圍已驗證'));
    expect(preview.metadata?.exportFormatVersion, 2);
    expect(preview.metadata?.databaseSchemaVersion, 20);
    expect(preview.metadata?.backupScopeVersion, 6);
    expect(preview.metadata?.coverageComplete, isTrue);
    expect(preview.tableRowCounts['accounts'], 1);
    expect(preview.tableRowCounts['transactions'], 1);
    expect(preview.tableRowCounts['cloud_invoice_drafts'], 1);
    expect(preview.tableRowCounts['wallet_top_up_profiles'], 0);
    expect(preview.tableRowCounts['wallet_top_up_suggestions'], 0);
    expect(preview.tableRowCounts['wallet_top_up_audits'], 0);
  });

  test('legacy Scope V5 coverage remains previewable', () async {
    final preview = await const FullRestorePreviewService().previewBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(_legacyScopeV5Envelope()))),
      sourceUri: 'provider:legacy-v5-backup.json',
      fileName: 'legacy-v5-backup.json',
    );

    expect(preview.isValid, isTrue);
    expect(preview.metadata?.databaseSchemaVersion, 19);
    expect(preview.metadata?.backupScopeVersion, 5);
    expect(preview.tableRowCounts, isNot(contains('wallet_top_up_profiles')));
    expect(preview.tableRowCounts, isNot(contains('wallet_top_up_suggestions')));
    expect(preview.tableRowCounts, isNot(contains('wallet_top_up_audits')));
  });

  test('legacy Scope V4 coverage remains previewable', () async {
    final preview = await const FullRestorePreviewService().previewBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(_legacyScopeV4Envelope()))),
      sourceUri: 'provider:legacy-v4-backup.json',
      fileName: 'legacy-v4-backup.json',
    );

    expect(preview.isValid, isTrue);
    expect(preview.metadata?.databaseSchemaVersion, 18);
    expect(preview.metadata?.backupScopeVersion, 4);
    expect(
      preview.tableRowCounts,
      isNot(contains('debit_card_settlement_confirmation_audits')),
    );
  });

  test('legacy Scope V3 coverage remains previewable', () async {
    final preview = await const FullRestorePreviewService().previewBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(_legacyScopeV3Envelope()))),
      sourceUri: 'provider:legacy-v3-backup.json',
      fileName: 'legacy-v3-backup.json',
    );

    expect(preview.isValid, isTrue);
    expect(preview.metadata?.databaseSchemaVersion, 17);
    expect(preview.metadata?.backupScopeVersion, 3);
    expect(
      preview.tableRowCounts,
      isNot(contains('debit_card_authorization_audits')),
    );
  });

  test('legacy Scope V2 coverage remains previewable', () async {
    final preview = await const FullRestorePreviewService().previewBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(_legacyScopeV2Envelope()))),
      sourceUri: 'provider:legacy-v2-backup.json',
      fileName: 'legacy-v2-backup.json',
    );

    expect(preview.isValid, isTrue);
    expect(preview.metadata?.databaseSchemaVersion, 16);
    expect(preview.metadata?.backupScopeVersion, 2);
    expect(preview.tableRowCounts, isNot(contains('debit_card_profiles')));
    expect(preview.tableRowCounts, isNot(contains('debit_card_settlements')));
  });

  test('Scope V6 preview rejects a missing managed table array', () async {
    final envelope = _scopeV6Envelope();
    (envelope['data']! as Map<String, Object?>).remove(
      'wallet_top_up_audits',
    );

    final preview = await const FullRestorePreviewService().previewBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      sourceUri: 'provider:partial-v6.json',
      fileName: 'partial-v6.json',
    );

    expect(preview.isValid, isFalse);
    expect(preview.message, contains('wallet_top_up_audits'));
  });

  test('preview rejects unknown-table coverage state', () async {
    final envelope = _scopeV6Envelope();
    final metadata = envelope['metadata']! as Map<String, Object?>;
    metadata['unknown_tables'] = <String>['future_private_table'];
    metadata['coverage_complete'] = false;

    final preview = await const FullRestorePreviewService().previewBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      sourceUri: 'provider:unknown-table-v6.json',
      fileName: 'unknown-table-v6.json',
    );

    expect(preview.isValid, isFalse);
    expect(preview.message, contains('範圍未通過完整性驗證'));
  });
}

Map<String, Object?> _scopeV6Envelope() {
  final data = <String, Object?>{
    for (final tableName in FullBackupScope.legacyScopeV6TableNames)
      tableName: <Object?>[],
  };
  data['accounts'] = <Object?>[
    <String, Object?>{'id': 'cash'},
  ];
  data['transactions'] = <Object?>[
    <String, Object?>{'id': 'tx-1'},
  ];
  data['cloud_invoice_drafts'] = <Object?>[
    <String, Object?>{'id': 'draft-1'},
  ];

  return _envelope(
    schemaVersion: 20,
    scopeVersion: 6,
    includedTables: FullBackupScope.legacyScopeV6TableNames,
    data: data,
  );
}

Map<String, Object?> _legacyScopeV5Envelope() {
  final data = <String, Object?>{
    for (final tableName in FullBackupScope.legacyScopeV5TableNames)
      tableName: <Object?>[],
  };
  data['accounts'] = <Object?>[<String, Object?>{'id': 'cash'}];
  data['transactions'] = <Object?>[<String, Object?>{'id': 'tx-1'}];
  return _envelope(
    schemaVersion: 19,
    scopeVersion: 5,
    includedTables: FullBackupScope.legacyScopeV5TableNames,
    data: data,
  );
}

Map<String, Object?> _legacyScopeV4Envelope() {
  final data = <String, Object?>{
    for (final tableName in FullBackupScope.legacyScopeV4TableNames)
      tableName: <Object?>[],
  };
  data['accounts'] = <Object?>[<String, Object?>{'id': 'cash'}];
  data['transactions'] = <Object?>[<String, Object?>{'id': 'tx-1'}];
  return _envelope(
    schemaVersion: 18,
    scopeVersion: 4,
    includedTables: FullBackupScope.legacyScopeV4TableNames,
    data: data,
  );
}

Map<String, Object?> _legacyScopeV3Envelope() {
  final data = <String, Object?>{
    for (final tableName in FullBackupScope.legacyScopeV3TableNames)
      tableName: <Object?>[],
  };
  data['accounts'] = <Object?>[
    <String, Object?>{'id': 'cash'},
  ];
  data['transactions'] = <Object?>[
    <String, Object?>{'id': 'tx-1'},
  ];
  return _envelope(
    schemaVersion: 17,
    scopeVersion: 3,
    includedTables: FullBackupScope.legacyScopeV3TableNames,
    data: data,
  );
}

Map<String, Object?> _legacyScopeV2Envelope() {
  final data = <String, Object?>{
    for (final tableName in FullBackupScope.legacyScopeV2TableNames)
      tableName: <Object?>[],
  };
  data['accounts'] = <Object?>[
    <String, Object?>{'id': 'cash'},
  ];
  data['transactions'] = <Object?>[
    <String, Object?>{'id': 'tx-1'},
  ];
  return _envelope(
    schemaVersion: 16,
    scopeVersion: 2,
    includedTables: FullBackupScope.legacyScopeV2TableNames,
    data: data,
  );
}

Map<String, Object?> _envelope({
  required int schemaVersion,
  required int scopeVersion,
  required List<String> includedTables,
  required Map<String, Object?> data,
}) {
  return <String, Object?>{
    'metadata': <String, Object?>{
      'export_format_version': FullBackupScope.exportFormatVersion,
      'app_name': FullBackupService.appName,
      'app_version': '4.14.2+395',
      'phase': 'P4.14.2',
      'database_schema_version': schemaVersion,
      'created_at': '2026-07-04T09:00:00.000Z',
      'source_platform': 'android',
      'export_mode': FullBackupService.exportModeFullBackup,
      'backup_scope_version': scopeVersion,
      'included_tables': includedTables,
      'included_present_tables': includedTables,
      'excluded_present_tables': <String>[],
      'missing_optional_tables': <String>[],
      'unknown_tables': <String>[],
      'missing_required_tables': <String>[],
      'coverage_complete': true,
    },
    'data': data,
  };
}
