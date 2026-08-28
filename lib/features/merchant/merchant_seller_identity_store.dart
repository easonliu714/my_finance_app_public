import 'merchant_record.dart';

abstract class MerchantSellerIdentityStore {
  Future<List<MerchantRecord>> listMerchants({bool includeArchived = false});

  Future<MerchantRecord?> findBySellerIdentifier(
    String sellerIdentifier, {
    bool includeArchived = false,
  });

  Future<void> upsertMerchant(MerchantRecord merchant);
}
