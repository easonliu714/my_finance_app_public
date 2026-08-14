import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_migration.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository_factory.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_sqlite_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CreditCardInstallmentRepositoryFactory', () {
    test('defaults to preview-safe in-memory repository', () {
      const factory = CreditCardInstallmentRepositoryFactory();

      final repository = factory.create();

      expect(repository, isA<InMemoryCreditCardInstallmentRepository>());
    });

    test('throws when sqlite mode has no database provider', () {
      const factory = CreditCardInstallmentRepositoryFactory(mode: CreditCardInstallmentRepositoryMode.sqlite);

      expect(factory.create, throwsA(isA<InstallmentRepositoryFactoryFailure>()));
    });

    test('creates sqlite repository when database provider is explicit', () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await createCreditCardInstallmentTables(db);
      final factory = CreditCardInstallmentRepositoryFactory(
        mode: CreditCardInstallmentRepositoryMode.sqlite,
        databaseProvider: () async => db,
      );

      final repository = factory.create();

      expect(repository, isA<SQLiteCreditCardInstallmentRepository>());
    });
  });
}
