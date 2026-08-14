import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/full_backup_scope.dart';

void main() {
  test('Scope V7 preserves Scope V6 and adds only execution ledger', () {
    expect(FullBackupScope.backupScopeVersion, 7);
    expect(FullBackupScope.supportedBackupScopeVersions, contains(6));
    expect(
      FullBackupScope.backupTableNames,
      <String>[
        ...FullBackupScope.legacyScopeV6TableNames,
        'wallet_top_up_executions',
      ],
    );
  });

  test('production restore uses V7 guard and validates execution links', () {
    final actionSource = File(
      'lib/features/backup/backup_migration_actions.dart',
    ).readAsStringSync();
    final wrapperSource = File(
      'lib/features/backup/full_restore_service_v7.dart',
    ).readAsStringSync();

    expect(actionSource, contains('const FullRestoreServiceV7()'));
    expect(wrapperSource, contains("backup_scope_version'] == 6"));
    expect(wrapperSource, contains('dropWalletTopUpExecutionImmutabilityTriggers'));
    expect(wrapperSource, contains('createWalletTopUpExecutionImmutabilityTriggers'));
    for (final column in <String>[
      'source_transaction_id',
      'generated_transfer_transaction_id',
      'profile_id',
      'target_account_id',
      'funding_account_id',
    ]) {
      expect(wrapperSource, contains(column));
    }
  });
}
