import 'merchant_record.dart';

abstract class MerchantStore {
  Future<List<MerchantRecord>> listMerchants({bool includeArchived = false});
  Future<void> upsertMerchant(MerchantRecord merchant);
  Future<void> archiveMerchant(String id);
}
