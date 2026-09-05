import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';

void main() {
  test('legacy Scope V7 preserves Scope V6 and adds only execution ledger', () {
    expect(FullBackupScope.backupScopeVersion, 8);
    expect(FullBackupScope.supportedBackupScopeVersions, containsAll(<int>{6, 7, 8}));
    expect(
      FullBackupScope.legacyScopeV7TableNames,
      <String>[
        ...FullBackupScope.legacyScopeV6TableNames,
        'wallet_top_up_executions',
      ],
    );
  });

  test('production restore uses V8 wrapper while preserving V7 execution guards', () {
    final actionSource = File(
      'lib/features/backup/backup_migration_actions.dart',
    ).readAsStringSync();
    final v8Source = File(
      'lib/features/backup/full_restore_service_v8.dart',
    ).readAsStringSync();
    final v7Source = File(
      'lib/features/backup/full_restore_service_v7.dart',
    ).readAsStringSync();

    expect(actionSource, contains('const FullRestoreServiceV8()'));
    expect(v8Source, contains('extends FullRestoreServiceV7'));
    expect(v7Source, contains("backup_scope_version'] == 6"));
    expect(v7Source, contains('dropWalletTopUpExecutionImmutabilityTriggers'));
    expect(v7Source, contains('createWalletTopUpExecutionImmutabilityTriggers'));
    for (final column in <String>[
      'source_transaction_id',
      'generated_transfer_transaction_id',
      'profile_id',
      'target_account_id',
      'funding_account_id',
    ]) {
      expect(v7Source, contains(column));
    }
  });
}
