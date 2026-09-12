import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_master_binding_service.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_merchant_binding_flow.dart';
import 'package:my_finance_app/features/invoice/invoice_seller_tax_id_confirmation.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:my_finance_app/features/merchant/merchant_seller_identity_store.dart';

void main() {
  InvoiceMerchantDecisionSelection recognition(String taxId) =>
      InvoiceMerchantDecisionSelection(
        option: InvoiceMerchantDecisionOption.recognition,
        displayName: '測試商家',
        sellerTaxId: taxId,
        invoiceLiteral: 'OCR literal merchant',
        requiresMerchantBindingConfirmation: true,
      );

  test('recognition bind is blocked before independent sellerTaxId authority', () async {
    final store = _MemoryMerchantStore();
    final flow = InvoiceRecognitionMerchantBindingFlow(
      bindingService: InvoiceMerchantMasterBindingService(store: store),
    );
    final confirmation = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '31655572',
      currentSourceToken: 'OCR',
    );
    final result = await flow.bind(
      selection: recognition('31655572'),
      sellerTaxIdConfirmation: confirmation,
    );
    expect(result.allowed, isFalse);
    expect(result.reasonCode, 'SELLER_TAX_ID_AUTHORITY_REQUIRED');
    expect(result.writesFormalTransaction, isFalse);
    expect(await store.listMerchants(), isEmpty);
  });

  test('explicit confirmation enables recognition MerchantBrand bind only', () async {
    final store = _MemoryMerchantStore();
    final flow = InvoiceRecognitionMerchantBindingFlow(
      bindingService: InvoiceMerchantMasterBindingService(store: store),
    );
    final confirmation = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '31655572',
      currentSourceToken: 'OCR',
    ).confirmCurrent();
    final result = await flow.bind(
      selection: recognition('31655572'),
      sellerTaxIdConfirmation: confirmation,
      consumerFacingMerchantName: '消費者品牌名稱',
    );
    expect(result.isSuccess, isTrue);
    expect(result.writesFormalTransaction, isFalse);
    final merchant = await store.findBySellerIdentifier('31655572');
    expect(merchant, isNotNull);
    final storedMerchant = merchant!;
    expect(storedMerchant.name, '消費者品牌名稱');
    expect(storedMerchant.sellerIdentifier, '31655572');
  });

  test('stale 31655572 selection cannot bind after current value becomes 60282181', () async {
    final store = _MemoryMerchantStore();
    final flow = InvoiceRecognitionMerchantBindingFlow(
      bindingService: InvoiceMerchantMasterBindingService(store: store),
    );
    final confirmed316 = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '31655572',
      currentSourceToken: 'OCR',
    ).confirmCurrent();
    final current602 = confirmed316.withCurrent(
      sellerTaxId: '60282181',
      sourceToken: 'OCR',
    );
    final result = await flow.bind(
      selection: recognition('31655572'),
      sellerTaxIdConfirmation: current602,
    );
    expect(result.allowed, isFalse);
    expect(result.reasonCode, 'STALE_SELLER_TAX_ID_SELECTION');
    expect(await store.listMerchants(), isEmpty);
  });

  test('60282181 can bind only after fresh explicit confirmation', () async {
    final store = _MemoryMerchantStore();
    final flow = InvoiceRecognitionMerchantBindingFlow(
      bindingService: InvoiceMerchantMasterBindingService(store: store),
    );
    final confirmation = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '60282181',
      currentSourceToken: 'OCR',
    ).confirmCurrent();
    final result = await flow.bind(
      selection: recognition('60282181'),
      sellerTaxIdConfirmation: confirmation,
    );
    expect(result.isSuccess, isTrue);
    expect(result.writesFormalTransaction, isFalse);
    expect(await store.findBySellerIdentifier('60282181'), isNotNull);
  });
}

class _MemoryMerchantStore implements MerchantSellerIdentityStore {
  final List<MerchantRecord> _items = <MerchantRecord>[];

  @override
  Future<MerchantRecord?> findBySellerIdentifier(
    String sellerIdentifier, {
    bool includeArchived = false,
  }) async {
    for (final merchant in _items) {
      if (merchant.sellerIdentifier == sellerIdentifier &&
          (includeArchived || !merchant.isArchived)) {
        return merchant;
      }
    }
    return null;
  }

  @override
  Future<List<MerchantRecord>> listMerchants({bool includeArchived = false}) async =>
      _items.where((merchant) => includeArchived || !merchant.isArchived).toList();

  @override
  Future<void> upsertMerchant(MerchantRecord merchant) async {
    final index = _items.indexWhere((item) => item.id == merchant.id);
    if (index < 0) {
      _items.add(merchant);
    } else {
      _items[index] = merchant;
    }
  }
}
