import 'package:sqflite/sqflite.dart';

import 'credit_card_installment_repository.dart';
import 'credit_card_installment_sqlite_repository.dart';

enum CreditCardInstallmentRepositoryMode {
  previewSafeInMemory,
  sqlite,
}

class CreditCardInstallmentRepositoryFactory {
  const CreditCardInstallmentRepositoryFactory({
    this.mode = CreditCardInstallmentRepositoryMode.previewSafeInMemory,
    this.databaseProvider,
  });

  final CreditCardInstallmentRepositoryMode mode;
  final Future<Database> Function()? databaseProvider;

  CreditCardInstallmentRepository create() {
    switch (mode) {
      case CreditCardInstallmentRepositoryMode.previewSafeInMemory:
        return InMemoryCreditCardInstallmentRepository();
      case CreditCardInstallmentRepositoryMode.sqlite:
        final provider = databaseProvider;
        if (provider == null) {
          throw const InstallmentRepositoryFactoryFailure('SQLite installment repository requires a database provider.');
        }
        return SQLiteCreditCardInstallmentRepository(provider);
    }
  }
}

class InstallmentRepositoryFactoryFailure implements Exception {
  const InstallmentRepositoryFactoryFailure(this.message);

  final String message;

  @override
  String toString() => 'InstallmentRepositoryFactoryFailure: $message';
}
