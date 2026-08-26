import '../merchant/canonical_merchant_repository.dart';
import '../merchant/merchant_record.dart';
import '../merchant/merchant_seller_identity_store.dart';
import 'taiwan_tax_id.dart';

enum InvoiceMerchantMasterBindingStatus {
  created,
  boundExistingMerchant,
  selectedExistingBinding,
  conflict,
  invalidInput,
}

class InvoiceMerchantMasterBindingResult {
  const InvoiceMerchantMasterBindingResult({
    required this.status,
    this.merchant,
    this.message = '',
  });

  final InvoiceMerchantMasterBindingStatus status;
  final MerchantRecord? merchant;
  final String message;

  bool get isSuccess =>
      status == InvoiceMerchantMasterBindingStatus.created ||
      status == InvoiceMerchantMasterBindingStatus.boundExistingMerchant ||
      status == InvoiceMerchantMasterBindingStatus.selectedExistingBinding;
}

class InvoiceMerchantMasterBindingService {
  const InvoiceMerchantMasterBindingService({
    this.store,
  });

  final MerchantSellerIdentityStore? store;

  MerchantSellerIdentityStore get _store =>
      store ?? CanonicalMerchantRepository.instance;

  Future<InvoiceMerchantMasterBindingResult> bind({
    required String merchantName,
    required String sellerTaxId,
  }) async {
    final name = merchantName.trim();
    final taxId = sellerTaxId.replaceAll(RegExp(r'[^0-9]'), '');
    if (name.isEmpty ||
        !isTaiwanTaxIdFormat(taxId) ||
        !hasValidTaiwanTaxIdChecksum(taxId)) {
      return const InvoiceMerchantMasterBindingResult(
        status: InvoiceMerchantMasterBindingStatus.invalidInput,
        message: '商家名稱不可空白，且賣方統編必須是通過校驗的 8 碼統編。',
      );
    }

    final existingByTax = await _store.findBySellerIdentifier(
      taxId,
      includeArchived: true,
    );
    if (existingByTax != null) {
      if (_normalizeName(existingByTax.name) != _normalizeName(name)) {
        return InvoiceMerchantMasterBindingResult(
          status: InvoiceMerchantMasterBindingStatus.conflict,
          merchant: existingByTax,
          message:
              '賣方統編 $taxId 已綁定「${existingByTax.displayName}」，不可自動改綁到「$name」。',
        );
      }
      if (existingByTax.isArchived) {
        final restored = existingByTax.copyWith(
          name: name,
          isArchived: false,
          sellerIdentifier: taxId,
        );
        await _store.upsertMerchant(restored);
        return InvoiceMerchantMasterBindingResult(
          status: InvoiceMerchantMasterBindingStatus.boundExistingMerchant,
          merchant: restored,
          message: '已恢復既有商家並保留統編綁定。',
        );
      }
      return InvoiceMerchantMasterBindingResult(
        status: InvoiceMerchantMasterBindingStatus.selectedExistingBinding,
        merchant: existingByTax,
        message: '此賣方統編已綁定既有商家。',
      );
    }

    final stored = await _store.listMerchants(includeArchived: true);
    MerchantRecord? sameName;
    for (final merchant in stored) {
      if (_normalizeName(merchant.name) == _normalizeName(name)) {
        sameName = merchant;
        break;
      }
    }

    if (sameName != null) {
      final existingTax = sameName.sellerIdentifier.trim();
      if (existingTax.isNotEmpty && existingTax != taxId) {
        return InvoiceMerchantMasterBindingResult(
          status: InvoiceMerchantMasterBindingStatus.conflict,
          merchant: sameName,
          message:
              '商家「${sameName.displayName}」已綁定統編 $existingTax，不可直接改為 $taxId。',
        );
      }
      final bound = sameName.copyWith(
        name: name,
        sellerIdentifier: taxId,
        isArchived: false,
      );
      await _store.upsertMerchant(bound);
      return InvoiceMerchantMasterBindingResult(
        status: InvoiceMerchantMasterBindingStatus.boundExistingMerchant,
        merchant: bound,
        message: '已將賣方統編綁定到既有商家。',
      );
    }

    final created = MerchantRecord(
      id: 'merchant-tax-$taxId',
      name: name,
      sellerIdentifier: taxId,
      note: '由發票覆核畫面經使用者明確確認建立',
    );
    await _store.upsertMerchant(created);
    return InvoiceMerchantMasterBindingResult(
      status: InvoiceMerchantMasterBindingStatus.created,
      merchant: created,
      message: '已新增商家並綁定賣方統編。',
    );
  }

  static String _normalizeName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s·・_\-－—–]'), '')
      .replaceAll('臺', '台');
}
