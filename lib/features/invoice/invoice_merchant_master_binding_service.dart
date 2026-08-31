import '../merchant/canonical_merchant_repository.dart';
import '../merchant/merchant_record.dart';
import '../merchant/merchant_seller_identity_store.dart';
import 'invoice_merchant_identity_review_service.dart';
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
    this.officialLegalName = '',
    this.registryVersion = '',
    this.registryCoverage = '',
  });

  final InvoiceMerchantMasterBindingStatus status;
  final MerchantRecord? merchant;
  final String message;
  final String officialLegalName;
  final String registryVersion;
  final String registryCoverage;

  bool get isSuccess =>
      status == InvoiceMerchantMasterBindingStatus.created ||
      status == InvoiceMerchantMasterBindingStatus.boundExistingMerchant ||
      status == InvoiceMerchantMasterBindingStatus.selectedExistingBinding;
}

class InvoiceMerchantMasterBindingService {
  const InvoiceMerchantMasterBindingService({
    this.store,
    this.identityReviewService,
  });

  final MerchantSellerIdentityStore? store;
  final InvoiceMerchantIdentityReviewPort? identityReviewService;

  MerchantSellerIdentityStore get _store =>
      store ?? CanonicalMerchantRepository.instance;

  InvoiceMerchantIdentityReviewPort? get _identityReview =>
      identityReviewService ??
      (store == null ? const InvoiceMerchantIdentityReviewService() : null);

  Future<InvoiceMerchantMasterBindingResult> bind({
    required String merchantName,
    required String sellerTaxId,
    bool trustedQrSellerIdentifier = false,
    String sourceReference = '',
  }) async {
    final name = merchantName.trim();
    final taxId = sellerTaxId.replaceAll(RegExp(r'[^0-9]'), '');
    final formatValid = isTaiwanTaxIdFormat(taxId);
    final checksumValid = formatValid && hasValidTaiwanTaxIdChecksum(taxId);
    if (name.isEmpty ||
        !formatValid ||
        (!checksumValid && !trustedQrSellerIdentifier)) {
      return InvoiceMerchantMasterBindingResult(
        status: InvoiceMerchantMasterBindingStatus.invalidInput,
        message: trustedQrSellerIdentifier
            ? '商家名稱不可空白，且 QR 賣方識別碼必須是 8 碼數字。'
            : '商家名稱不可空白，且人工／OCR 賣方統編必須是通過校驗的 8 碼統編。',
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
        return _withIdentityContext(
          status: InvoiceMerchantMasterBindingStatus.boundExistingMerchant,
          merchant: restored,
          baseMessage: _successMessage(
            '已恢復既有商家並保留統編綁定。',
            checksumValid: checksumValid,
            trustedQrSellerIdentifier: trustedQrSellerIdentifier,
          ),
          sellerTaxId: taxId,
          literalMerchantText: name,
          trustedQrSellerIdentifier: trustedQrSellerIdentifier,
          sourceReference: sourceReference,
        );
      }
      return _withIdentityContext(
        status: InvoiceMerchantMasterBindingStatus.selectedExistingBinding,
        merchant: existingByTax,
        baseMessage: _successMessage(
          '此賣方統編已綁定既有商家。',
          checksumValid: checksumValid,
          trustedQrSellerIdentifier: trustedQrSellerIdentifier,
        ),
        sellerTaxId: taxId,
        literalMerchantText: name,
        trustedQrSellerIdentifier: trustedQrSellerIdentifier,
        sourceReference: sourceReference,
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
      return _withIdentityContext(
        status: InvoiceMerchantMasterBindingStatus.boundExistingMerchant,
        merchant: bound,
        baseMessage: _successMessage(
          '已將賣方統編綁定到既有商家。',
          checksumValid: checksumValid,
          trustedQrSellerIdentifier: trustedQrSellerIdentifier,
        ),
        sellerTaxId: taxId,
        literalMerchantText: name,
        trustedQrSellerIdentifier: trustedQrSellerIdentifier,
        sourceReference: sourceReference,
      );
    }

    final created = MerchantRecord(
      id: 'merchant-tax-$taxId',
      name: name,
      sellerIdentifier: taxId,
      note: trustedQrSellerIdentifier && !checksumValid
          ? '由發票覆核畫面經使用者明確確認建立；賣方識別碼來自 QR 原始資料，未通過傳統統編 checksum'
          : '由發票覆核畫面經使用者明確確認建立',
    );
    await _store.upsertMerchant(created);
    return _withIdentityContext(
      status: InvoiceMerchantMasterBindingStatus.created,
      merchant: created,
      baseMessage: _successMessage(
        '已新增商家並綁定賣方統編。',
        checksumValid: checksumValid,
        trustedQrSellerIdentifier: trustedQrSellerIdentifier,
      ),
      sellerTaxId: taxId,
      literalMerchantText: name,
      trustedQrSellerIdentifier: trustedQrSellerIdentifier,
      sourceReference: sourceReference,
    );
  }

  Future<InvoiceMerchantMasterBindingResult> _withIdentityContext({
    required InvoiceMerchantMasterBindingStatus status,
    required MerchantRecord merchant,
    required String baseMessage,
    required String sellerTaxId,
    required String literalMerchantText,
    required bool trustedQrSellerIdentifier,
    required String sourceReference,
  }) async {
    final service = _identityReview;
    if (service == null) {
      return InvoiceMerchantMasterBindingResult(
        status: status,
        merchant: merchant,
        message: baseMessage,
      );
    }

    final reference = sourceReference.trim().isEmpty
        ? 'invoice-review-binding:$sellerTaxId:${_normalizeName(literalMerchantText)}'
        : sourceReference.trim();
    final context = await service.confirmBinding(
      merchant: merchant,
      sellerIdentifier: sellerTaxId,
      literalMerchantText: literalMerchantText,
      evidenceSource: trustedQrSellerIdentifier
          ? 'invoice_qr_explicit_binding'
          : 'invoice_review_explicit_binding',
      sourceReference: reference,
    );
    final legalName = context.decision.officialLegalNameSuggestion.trim();
    final registrySuffix = legalName.isEmpty
        ? ''
        : ' 官方登記名稱：$legalName（僅供佐證，不覆寫發票商家文字）。';
    final subsetSuffix = context.isValidationSubset
        ? ' 目前官方資料來源為 P4.20 實機驗證子集。'
        : '';
    return InvoiceMerchantMasterBindingResult(
      status: status,
      merchant: merchant,
      message: '$baseMessage$registrySuffix$subsetSuffix',
      officialLegalName: legalName,
      registryVersion: context.registryVersion,
      registryCoverage: context.registryCoverage,
    );
  }

  static String _successMessage(
    String base, {
    required bool checksumValid,
    required bool trustedQrSellerIdentifier,
  }) {
    if (trustedQrSellerIdentifier && !checksumValid) {
      return '$base 此 8 碼識別碼由 QR 原始資料提供，未通過傳統統編 checksum，已保留 QR provenance。';
    }
    return base;
  }

  static String _normalizeName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s·・_\-－—–]'), '')
      .replaceAll('臺', '台');
}
