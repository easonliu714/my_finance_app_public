enum InvoiceMerchantDecisionOption {
  recognition,
  existingMerchantBrand,
  officialRegistry,
}

class InvoiceMerchantDecisionInput {
  const InvoiceMerchantDecisionInput({
    required this.recognizedMerchantName,
    required this.sellerTaxId,
    required this.recognitionSourceLabel,
    this.existingMerchantBrand = '',
    this.officialLegalName = '',
    this.officialEntityLabel = '',
    this.officialParentSellerTaxId = '',
    this.officialSource = '',
    this.officialDataDate = '',
  });

  final String recognizedMerchantName;
  final String sellerTaxId;
  final String recognitionSourceLabel;
  final String existingMerchantBrand;
  final String officialLegalName;
  final String officialEntityLabel;
  final String officialParentSellerTaxId;
  final String officialSource;
  final String officialDataDate;
}

class InvoiceMerchantDecisionCandidate {
  const InvoiceMerchantDecisionCandidate({
    required this.option,
    required this.title,
    required this.displayName,
    required this.sellerTaxId,
    required this.available,
    required this.requiresMerchantBindingConfirmation,
    this.supportingLabel = '',
  });

  final InvoiceMerchantDecisionOption option;
  final String title;
  final String displayName;
  final String sellerTaxId;
  final bool available;
  final bool requiresMerchantBindingConfirmation;
  final String supportingLabel;
}

class InvoiceMerchantDecisionSelection {
  const InvoiceMerchantDecisionSelection({
    required this.option,
    required this.displayName,
    required this.sellerTaxId,
    required this.invoiceLiteral,
    required this.requiresMerchantBindingConfirmation,
  });

  final InvoiceMerchantDecisionOption option;
  final String displayName;
  final String sellerTaxId;

  /// The literal merchant text detected from the invoice stays available even
  /// when the user explicitly chooses an existing MerchantBrand or an official
  /// Registry legal name. Selection must not silently destroy the source text.
  final String invoiceLiteral;

  /// Recognition and official-data candidates may request a create/bind
  /// operation, but only through a second explicit confirmation. Merely
  /// displaying or selecting either candidate never writes MerchantBrand state.
  final bool requiresMerchantBindingConfirmation;

  /// Merchant choice only prepares review/binding intent. It can never bypass
  /// the frozen accounting boundary into a formal transaction write.
  bool get writesFormalTransaction => false;
}

class InvoiceMerchantDecisionComposerState {
  const InvoiceMerchantDecisionComposerState({
    required this.input,
    required this.candidates,
    this.selectedOption,
  });

  final InvoiceMerchantDecisionInput input;
  final List<InvoiceMerchantDecisionCandidate> candidates;
  final InvoiceMerchantDecisionOption? selectedOption;

  bool get hasExplicitSelection => selectedOption != null;

  InvoiceMerchantDecisionCandidate candidateFor(
    InvoiceMerchantDecisionOption option,
  ) => candidates.firstWhere((candidate) => candidate.option == option);

  InvoiceMerchantDecisionComposerState select(
    InvoiceMerchantDecisionOption option,
  ) {
    final candidate = candidateFor(option);
    if (!candidate.available) {
      throw StateError('MERCHANT_DECISION_OPTION_UNAVAILABLE_${option.name}');
    }
    return InvoiceMerchantDecisionComposerState(
      input: input,
      candidates: candidates,
      selectedOption: option,
    );
  }

  InvoiceMerchantDecisionSelection? get selection {
    final option = selectedOption;
    if (option == null) return null;
    final candidate = candidateFor(option);
    return InvoiceMerchantDecisionSelection(
      option: option,
      displayName: candidate.displayName,
      sellerTaxId: candidate.sellerTaxId,
      invoiceLiteral: input.recognizedMerchantName.trim(),
      requiresMerchantBindingConfirmation:
          candidate.requiresMerchantBindingConfirmation,
    );
  }
}

/// P4.20.4 Merchant Decision Composer domain contract.
///
/// The composer deliberately has no implicit/default selection. It presents
/// three distinct identity layers and waits for an explicit user choice:
///
/// 1. this recognition result (OCR / AI / QR),
/// 2. an already-confirmed consumer MerchantBrand,
/// 3. official Registry legal/branch identity.
///
/// `invoice literal != MerchantBrand != official legal name` remains frozen.
class InvoiceMerchantDecisionComposer {
  const InvoiceMerchantDecisionComposer();

  InvoiceMerchantDecisionComposerState compose(
    InvoiceMerchantDecisionInput input,
  ) {
    final seller = _digits(input.sellerTaxId);
    final recognized = input.recognizedMerchantName.trim();
    final existing = input.existingMerchantBrand.trim();
    final official = input.officialLegalName.trim();

    final officialMeta = <String>[
      if (input.officialEntityLabel.trim().isNotEmpty)
        input.officialEntityLabel.trim(),
      if (input.officialParentSellerTaxId.trim().isNotEmpty)
        '總機構 ${_digits(input.officialParentSellerTaxId)}',
      if (input.officialDataDate.trim().isNotEmpty)
        '資料 ${input.officialDataDate.trim()}',
      if (input.officialSource.trim().isNotEmpty) input.officialSource.trim(),
    ].join(' · ');

    return InvoiceMerchantDecisionComposerState(
      input: input,
      candidates: <InvoiceMerchantDecisionCandidate>[
        InvoiceMerchantDecisionCandidate(
          option: InvoiceMerchantDecisionOption.recognition,
          title: '此次辨識結果',
          displayName: recognized,
          sellerTaxId: seller,
          available: recognized.isNotEmpty,
          requiresMerchantBindingConfirmation: true,
          supportingLabel: input.recognitionSourceLabel.trim(),
        ),
        InvoiceMerchantDecisionCandidate(
          option: InvoiceMerchantDecisionOption.existingMerchantBrand,
          title: '既有正式商家',
          displayName: existing,
          sellerTaxId: seller,
          available: existing.isNotEmpty,
          requiresMerchantBindingConfirmation: false,
          supportingLabel: 'MerchantBrand',
        ),
        InvoiceMerchantDecisionCandidate(
          option: InvoiceMerchantDecisionOption.officialRegistry,
          title: '官方登記資料',
          displayName: official,
          sellerTaxId: seller,
          available: official.isNotEmpty && seller.length == 8,
          requiresMerchantBindingConfirmation: true,
          supportingLabel: officialMeta,
        ),
      ],
    );
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}
