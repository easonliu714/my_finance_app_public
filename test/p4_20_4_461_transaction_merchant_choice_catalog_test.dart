import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_decision_composer.dart';
import 'package:my_finance_app/features/invoice/invoice_merchant_master_binding_service.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_merchant_binding_flow.dart';
import 'package:my_finance_app/features/invoice/invoice_seller_tax_id_confirmation.dart';
import 'package:my_finance_app/features/merchant/merchant_record.dart';
import 'package:my_finance_app/features/merchant/merchant_seller_identity_store.dart';
import 'package:my_finance_app/features/transaction/transaction_merchant_choice_catalog.dart';

void main() {
  test('recognition bind is visible to transaction merchant choice catalog without formal write', () async {
    final store = _MemoryMerchantStore();
    final flow = InvoiceRecognitionMerchantBindingFlow(
      bindingService: InvoiceMerchantMasterBindingService(store: store),
    );
    const initialConfirmation = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '31655572',
      currentSourceToken: 'OCR',
    );
    final result = await flow.bind(
      selection: const InvoiceMerchantDecisionSelection(
        option: InvoiceMerchantDecisionOption.recognition,
        displayName: 'OCR literal merchant',
        sellerTaxId: '31655572',
        invoiceLiteral: 'OCR literal merchant',
        requiresMerchantBindingConfirmation: true,
      ),
      sellerTaxIdConfirmation: initialConfirmation.confirmCurrent(),
      consumerFacingMerchantName: '新的消費者品牌',
    );

    expect(result.isSuccess, isTrue);
    expect(result.writesFormalTransaction, isFalse);

    final choices = await TransactionMerchantChoiceCatalog(
      store: store,
    ).listChoiceNames(
      fallbackNames: const <String>['不使用商家'],
    );

    expect(choices, contains('新的消費者品牌'));
    expect(choices, contains('不使用商家'));
    expect(choices.where((name) => name == '新的消費者品牌'), hasLength(1));

    final merchant = await store.findBySellerIdentifier('31655572');
    expect(merchant?.name, '新的消費者品牌');
    expect(merchant?.sellerIdentifier, '31655572');
  });

  test('catalog is read-only and only projects canonical merchant state', () async {
    final store = _MemoryMerchantStore();
    await store.upsertMerchant(
      MerchantRecord(
        id: 'merchant-tax-60282181',
        name: '第二個品牌',
        sellerIdentifier: '60282181',
      ),
    );

    final choices = await TransactionMerchantChoiceCatalog(
      store: store,
    ).listChoiceNames(
      fallbackNames: const <String>['不使用商家', '不使用商家'],
    );

    expect(choices, <String>['不使用商家', '第二個品牌']);
    expect(store.writeCount, 1);
  });
}

class _MemoryMerchantStore implements MerchantSellerIdentityStore {
  final List<MerchantRecord> _items = <MerchantRecord>[];
  int writeCount = 0;

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
  Future<List<MerchantRecord>> listMerchants({
    bool includeArchived = false,
  }) async =>
      _items
          .where((merchant) => includeArchived || !merchant.isArchived)
          .toList();

  @override
  Future<void> upsertMerchant(MerchantRecord merchant) async {
    writeCount += 1;
    final index = _items.indexWhere((item) => item.id == merchant.id);
    if (index < 0) {
      _items.add(merchant);
    } else {
      _items[index] = merchant;
    }
  }
}
