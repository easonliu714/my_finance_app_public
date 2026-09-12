import '../merchant/canonical_merchant_repository.dart';
import '../merchant/merchant_seller_identity_store.dart';

/// Canonical source for merchant choices shown by TransactionEntryPage.
///
/// The catalog is read-only. It never creates transactions or merchants; it
/// only projects the current canonical merchant repository into picker labels.
/// Merchant binding therefore remains a separate explicit action, while a
/// successfully bound MerchantBrand becomes selectable by the next transaction
/// entry read.
class TransactionMerchantChoiceCatalog {
  const TransactionMerchantChoiceCatalog({this.store});

  final MerchantSellerIdentityStore? store;

  MerchantSellerIdentityStore get _store =>
      store ?? CanonicalMerchantRepository.instance;

  Future<List<String>> listChoiceNames({
    Iterable<String> fallbackNames = const <String>[],
  }) async {
    final records = await _store.listMerchants();
    return normalizeTransactionMerchantChoiceNames(<String>[
      ...fallbackNames,
      ...records.map((record) => record.displayName),
    ]);
  }
}

List<String> normalizeTransactionMerchantChoiceNames(
  Iterable<String> values,
) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) continue;
    result.add(trimmed);
  }
  return result;
}
