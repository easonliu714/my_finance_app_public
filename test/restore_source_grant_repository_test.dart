import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/restore_source_grant.dart';
import 'package:my_finance_app/features/backup/restore_source_grant_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('saves loads and clears restore source grant', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    const repo = RestoreSourceGrantRepository();
    final grant = RestoreSourceGrant(
      uri: '/cloud/drive/my_finance_backup.json',
      displayName: 'my_finance_backup.json',
      grantedAt: DateTime.utc(2026, 6, 4, 12),
      sourceKind: RestoreSourceKind.documentFile,
      persisted: true,
      pathBacked: true,
    );

    expect(await repo.load(db), isNull);

    await repo.save(db, grant);
    final loaded = await repo.load(db);

    expect(loaded, isNotNull);
    expect(loaded!.uri, grant.uri);
    expect(loaded.displayName, grant.displayName);
    expect(loaded.grantedAt, grant.grantedAt);
    expect(loaded.sourceKind, RestoreSourceKind.documentFile);
    expect(loaded.persisted, isTrue);
    expect(loaded.pathBacked, isTrue);

    await repo.clear(db);
    expect(await repo.load(db), isNull);
  });
}
