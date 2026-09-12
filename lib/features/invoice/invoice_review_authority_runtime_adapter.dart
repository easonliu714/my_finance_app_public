import 'invoice_review_authority_contract.dart';
import 'invoice_review_form_view_model.dart';

class InvoiceReviewAuthorityRuntimeAdapter {
  const InvoiceReviewAuthorityRuntimeAdapter({
    this.contract = const InvoiceReviewAuthorityContract(),
  });

  final InvoiceReviewAuthorityContract contract;

  static const Set<InvoiceReviewFieldKey> transactionCoreFields =
      <InvoiceReviewFieldKey>{
        InvoiceReviewFieldKey.invoiceNumber,
        InvoiceReviewFieldKey.invoiceDate,
        InvoiceReviewFieldKey.invoiceTime,
        InvoiceReviewFieldKey.totalAmount,
      };

  static const Set<InvoiceReviewAuthorityFieldKind> transactionCoreKinds =
      <InvoiceReviewAuthorityFieldKind>{
        InvoiceReviewAuthorityFieldKind.invoiceId,
        InvoiceReviewAuthorityFieldKind.issueDate,
        InvoiceReviewAuthorityFieldKind.issueTime,
        InvoiceReviewAuthorityFieldKind.totalAmount,
      };

  InvoiceReviewAuthorityDecision evaluateTransactionDraft({
    required InvoiceReviewFormViewModel review,
    Set<InvoiceReviewFieldKey> explicitlyCorrectedFields = const {},
    Set<InvoiceReviewFieldKey> explicitlyAiSelectedFields = const {},
    bool explicitCoreConfirmation = false,
  }) {
    return contract.validateRequiredFields(
      fields: review.fields
          .map(
            (field) => authorityForField(
              field,
              explicitlyCorrected:
                  explicitlyCorrectedFields.contains(field.key),
              explicitlyAiSelected:
                  explicitlyAiSelectedFields.contains(field.key),
              explicitlyConfirmed:
                  explicitCoreConfirmation &&
                  transactionCoreFields.contains(field.key),
            ),
          )
          .whereType<InvoiceReviewFieldAuthority>(),
      requiredFields: transactionCoreKinds,
    );
  }

  InvoiceReviewFieldAuthority? authorityForField(
    InvoiceReviewFieldViewModel field, {
    bool explicitlyCorrected = false,
    bool explicitlyAiSelected = false,
    bool explicitlyConfirmed = false,
  }) {
    final kind = authorityKindFor(field.key);
    if (kind == null) return null;

    if (field.value.trim().isEmpty) {
      return InvoiceReviewFieldAuthority(
        kind: kind,
        state: InvoiceReviewAuthorityState.missing,
      );
    }

    if (explicitlyCorrected) {
      return InvoiceReviewFieldAuthority(
        kind: kind,
        state: InvoiceReviewAuthorityState.authoritative,
        source: InvoiceReviewAuthoritySource.explicitUserCorrection,
      );
    }

    if (explicitlyAiSelected) {
      if (kind == InvoiceReviewAuthorityFieldKind.merchant) {
        return const InvoiceReviewFieldAuthority(
          kind: InvoiceReviewAuthorityFieldKind.merchant,
          state: InvoiceReviewAuthorityState.supplemental,
          source: InvoiceReviewAuthoritySource.explicitAiSelection,
        );
      }
      return InvoiceReviewFieldAuthority(
        kind: kind,
        state: InvoiceReviewAuthorityState.authoritative,
        source: InvoiceReviewAuthoritySource.explicitAiSelection,
      );
    }

    if (_isQrEvidence(field)) {
      return InvoiceReviewFieldAuthority(
        kind: kind,
        state: InvoiceReviewAuthorityState.authoritative,
        source: InvoiceReviewAuthoritySource.qrPayload,
      );
    }

    if (explicitlyConfirmed && kind != InvoiceReviewAuthorityFieldKind.merchant) {
      return InvoiceReviewFieldAuthority(
        kind: kind,
        state: InvoiceReviewAuthorityState.authoritative,
        source: InvoiceReviewAuthoritySource.explicitUserConfirmation,
      );
    }

    return InvoiceReviewFieldAuthority(
      kind: kind,
      state: InvoiceReviewAuthorityState.supplemental,
      source: InvoiceReviewAuthoritySource.localOcr,
    );
  }

  InvoiceReviewAuthorityFieldKind? authorityKindFor(InvoiceReviewFieldKey key) {
    switch (key) {
      case InvoiceReviewFieldKey.invoiceNumber:
        return InvoiceReviewAuthorityFieldKind.invoiceId;
      case InvoiceReviewFieldKey.invoiceDate:
        return InvoiceReviewAuthorityFieldKind.issueDate;
      case InvoiceReviewFieldKey.invoiceTime:
        return InvoiceReviewAuthorityFieldKind.issueTime;
      case InvoiceReviewFieldKey.totalAmount:
        return InvoiceReviewAuthorityFieldKind.totalAmount;
      case InvoiceReviewFieldKey.sellerName:
        return InvoiceReviewAuthorityFieldKind.merchant;
      case InvoiceReviewFieldKey.sellerTaxId:
      case InvoiceReviewFieldKey.invoicePeriod:
      case InvoiceReviewFieldKey.randomCode:
        return null;
    }
  }

  String displayLabelForField(
    InvoiceReviewFieldViewModel field, {
    bool explicitlyCorrected = false,
    bool explicitlyAiSelected = false,
    bool explicitlyConfirmed = false,
    bool explicitMasterSelected = false,
  }) {
    if (explicitMasterSelected && field.key == InvoiceReviewFieldKey.sellerName) {
      return '權威：已新增／綁定正式商家主檔';
    }

    final authority = authorityForField(
      field,
      explicitlyCorrected: explicitlyCorrected,
      explicitlyAiSelected: explicitlyAiSelected,
      explicitlyConfirmed: explicitlyConfirmed,
    );
    if (authority == null) {
      if (explicitlyAiSelected) return '來源：AI（使用者明確採用）';
      if (explicitlyCorrected) return '來源：手動修正';
      return '';
    }

    if (authority.state == InvoiceReviewAuthorityState.missing) {
      return '權威：缺少欄位證據';
    }
    if (authority.state == InvoiceReviewAuthorityState.conflict) {
      return '權威：證據衝突，禁止 handoff';
    }
    if (authority.state == InvoiceReviewAuthorityState.supplemental) {
      if (authority.source == InvoiceReviewAuthoritySource.explicitAiSelection) {
        return '來源：AI 候選（尚未綁定正式商家）';
      }
      return '權威：本機 OCR 補充（待人工確認）';
    }

    switch (authority.source) {
      case InvoiceReviewAuthoritySource.qrPayload:
        return '權威：QR 原始資料';
      case InvoiceReviewAuthoritySource.explicitAiSelection:
        return '權威：使用者明確採用 AI';
      case InvoiceReviewAuthoritySource.explicitUserCorrection:
        return '權威：使用者明確修正';
      case InvoiceReviewAuthoritySource.explicitUserConfirmation:
        return '權威：已人工確認';
      case InvoiceReviewAuthoritySource.explicitMasterSelection:
        return '權威：已明確選擇正式主檔';
      case InvoiceReviewAuthoritySource.localOcr:
        return '權威：本機 OCR 補充（待人工確認）';
      case InvoiceReviewAuthoritySource.defaultProfile:
        return '權威：預設值僅供補充';
      case null:
        return '權威：尚未建立';
    }
  }

  String labelForKind(InvoiceReviewAuthorityFieldKind? kind) {
    switch (kind) {
      case InvoiceReviewAuthorityFieldKind.invoiceId:
        return '發票號碼';
      case InvoiceReviewAuthorityFieldKind.issueDate:
        return '發票日期';
      case InvoiceReviewAuthorityFieldKind.issueTime:
        return '交易時間';
      case InvoiceReviewAuthorityFieldKind.totalAmount:
        return '總金額';
      case InvoiceReviewAuthorityFieldKind.merchant:
        return '商家';
      case InvoiceReviewAuthorityFieldKind.lineItems:
        return '品項';
      case null:
        return '未知欄位';
    }
  }

  bool _isQrEvidence(InvoiceReviewFieldViewModel field) {
    final label = field.confidenceLabel.toUpperCase();
    return label.contains('QR');
  }
}
