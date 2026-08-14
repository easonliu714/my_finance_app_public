import '../../account/account_record.dart';
import '../../merchant/merchant_record.dart';
import '../../transaction/transaction_record.dart';
import 'cloud_invoice_persistence_models.dart';

abstract class CloudInvoiceTransactionPersistencePort {
  Future<TransactionRecord?> loadTransaction(String transactionId);

  Future<void> createDraft(CloudInvoiceDraftRecord draft);

  Future<void> removeDraft({
    required String draftId,
    required String operationKey,
  });

  Future<void> replaceTransaction(TransactionRecord transaction);

  Future<void> restoreTransaction(TransactionRecord beforeImage);
}

abstract class CloudInvoiceAccountPersistencePort {
  Future<AccountRecord?> loadAccount(String accountId);
}

abstract class CloudInvoiceMerchantPersistencePort {
  Future<MerchantRecord?> findByNormalizedName(String normalizedName);

  Future<CloudInvoiceMerchantCreationResult> createMerchant({
    required MerchantRecord merchant,
    required String operationKey,
  });

  Future<bool> hasExternalReferences(String merchantId);

  Future<void> compensateCreatedMerchant({
    required String merchantId,
    required String operationKey,
  });
}

abstract class CloudInvoiceMetadataPersistencePort {
  Future<void> upsertLink(CloudInvoiceMetadataLinkRecord link);

  Future<void> removeLinksForOperation(String operationKey);
}

abstract class CloudInvoiceOperationPersistencePort {
  Future<CloudInvoiceOperationRecord?> loadOperation(String operationKey);

  Future<void> saveOperation(CloudInvoiceOperationRecord operation);

  Future<void> saveBeforeImage(CloudInvoiceBeforeImageRecord beforeImage);

  Future<CloudInvoiceBeforeImageRecord?> loadBeforeImage(String rollbackToken);

  Future<void> appendAudit(CloudInvoiceAuditRecord audit);
}

abstract class CloudInvoicePersistenceClock {
  DateTime now();
}

abstract class CloudInvoicePersistenceIdGenerator {
  String nextId(String namespace);
}

class SystemCloudInvoicePersistenceClock
    implements CloudInvoicePersistenceClock {
  const SystemCloudInvoicePersistenceClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
