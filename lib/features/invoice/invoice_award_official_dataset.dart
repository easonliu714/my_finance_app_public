enum OfficialInvoiceAwardRuleKind {
  special,
  grand,
  first,
  additionalSixth,
  cloudExclusive,
}

class OfficialInvoiceAwardPeriod {
  const OfficialInvoiceAwardPeriod({
    required this.rocYear,
    required this.startMonth,
    required this.endMonth,
  });

  final int rocYear;
  final int startMonth;
  final int endMonth;

  String get id => '$rocYear-${startMonth.toString().padLeft(2, '0')}-${endMonth.toString().padLeft(2, '0')}';

  bool get isCanonical =>
      rocYear > 0 &&
      startMonth >= 1 &&
      startMonth <= 11 &&
      startMonth.isOdd &&
      endMonth == startMonth + 1;
}

class OfficialInvoiceAwardProvenance {
  const OfficialInvoiceAwardProvenance({
    required this.sourceId,
    required this.fetchedAt,
    required this.parserVersion,
    required this.contentSha256,
  });

  static const ministryOfFinanceSourceId = 'mof-tax-portal-invoice-awards';

  final String sourceId;
  final DateTime fetchedAt;
  final String parserVersion;
  final String contentSha256;
}

class OfficialInvoiceAwardRule {
  const OfficialInvoiceAwardRule({
    required this.kind,
    required this.number,
  });

  final OfficialInvoiceAwardRuleKind kind;
  final String number;

  bool get isStructurallyValid {
    switch (kind) {
      case OfficialInvoiceAwardRuleKind.additionalSixth:
        return RegExp(r'^\d{3}$').hasMatch(number);
      case OfficialInvoiceAwardRuleKind.special:
      case OfficialInvoiceAwardRuleKind.grand:
      case OfficialInvoiceAwardRuleKind.first:
      case OfficialInvoiceAwardRuleKind.cloudExclusive:
        return RegExp(r'^\d{8}$').hasMatch(number);
    }
  }
}

class OfficialInvoiceAwardDataset {
  const OfficialInvoiceAwardDataset({
    required this.period,
    required this.provenance,
    required this.rules,
    required this.published,
    required this.complete,
  });

  final OfficialInvoiceAwardPeriod period;
  final OfficialInvoiceAwardProvenance provenance;
  final List<OfficialInvoiceAwardRule> rules;
  final bool published;
  final bool complete;
}

enum OfficialInvoiceAwardDatasetValidationFailure {
  nonCanonicalPeriod,
  nonOfficialSource,
  unpublished,
  incomplete,
  invalidParserVersion,
  invalidFingerprint,
  malformedRule,
  missingGeneralAwardRules,
}

class OfficialInvoiceAwardDatasetValidation {
  const OfficialInvoiceAwardDatasetValidation._(this.failures);

  final Set<OfficialInvoiceAwardDatasetValidationFailure> failures;
  bool get isValid => failures.isEmpty;
}

class OfficialInvoiceAwardDatasetValidator {
  const OfficialInvoiceAwardDatasetValidator();

  OfficialInvoiceAwardDatasetValidation validate(OfficialInvoiceAwardDataset dataset) {
    final failures = <OfficialInvoiceAwardDatasetValidationFailure>{};
    if (!dataset.period.isCanonical) {
      failures.add(OfficialInvoiceAwardDatasetValidationFailure.nonCanonicalPeriod);
    }
    if (dataset.provenance.sourceId != OfficialInvoiceAwardProvenance.ministryOfFinanceSourceId) {
      failures.add(OfficialInvoiceAwardDatasetValidationFailure.nonOfficialSource);
    }
    if (!dataset.published) {
      failures.add(OfficialInvoiceAwardDatasetValidationFailure.unpublished);
    }
    if (!dataset.complete) {
      failures.add(OfficialInvoiceAwardDatasetValidationFailure.incomplete);
    }
    if (dataset.provenance.parserVersion.trim().isEmpty) {
      failures.add(OfficialInvoiceAwardDatasetValidationFailure.invalidParserVersion);
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(dataset.provenance.contentSha256)) {
      failures.add(OfficialInvoiceAwardDatasetValidationFailure.invalidFingerprint);
    }
    if (dataset.rules.any((rule) => !rule.isStructurallyValid)) {
      failures.add(OfficialInvoiceAwardDatasetValidationFailure.malformedRule);
    }

    final specialCount = dataset.rules.where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.special).length;
    final grandCount = dataset.rules.where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.grand).length;
    final firstCount = dataset.rules.where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.first).length;
    if (specialCount != 1 || grandCount != 1 || firstCount < 1) {
      failures.add(OfficialInvoiceAwardDatasetValidationFailure.missingGeneralAwardRules);
    }
    return OfficialInvoiceAwardDatasetValidation._(failures);
  }
}

enum OfficialInvoiceAwardMatchKind {
  notMatched,
  special,
  grand,
  first,
  second,
  third,
  fourth,
  fifth,
  sixth,
  additionalSixth,
  cloudExclusive,
  invalid,
}

class OfficialInvoiceAwardCandidate {
  const OfficialInvoiceAwardCandidate({
    required this.invoiceNumber,
    required this.period,
    required this.cloudExclusiveEligible,
  });

  final String invoiceNumber;
  final OfficialInvoiceAwardPeriod period;
  final bool cloudExclusiveEligible;

  String get normalizedNumber => invoiceNumber.replaceAll(RegExp(r'[^0-9]'), '');
  bool get isValid => normalizedNumber.length == 8 && period.isCanonical;
}

class OfficialInvoiceAwardMatch {
  const OfficialInvoiceAwardMatch(this.kind);

  final OfficialInvoiceAwardMatchKind kind;
  bool get isWinner => kind != OfficialInvoiceAwardMatchKind.notMatched && kind != OfficialInvoiceAwardMatchKind.invalid;
  bool get canCreateFormalTransaction => false;
}

class OfficialInvoiceAwardMatcher {
  const OfficialInvoiceAwardMatcher({required this.validator});

  final OfficialInvoiceAwardDatasetValidator validator;

  OfficialInvoiceAwardMatch match({
    required OfficialInvoiceAwardDataset dataset,
    required OfficialInvoiceAwardCandidate candidate,
  }) {
    if (!validator.validate(dataset).isValid || !candidate.isValid || candidate.period.id != dataset.period.id) {
      return const OfficialInvoiceAwardMatch(OfficialInvoiceAwardMatchKind.invalid);
    }

    final number = candidate.normalizedNumber;
    for (final rule in dataset.rules.where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.special)) {
      if (number == rule.number) return const OfficialInvoiceAwardMatch(OfficialInvoiceAwardMatchKind.special);
    }
    for (final rule in dataset.rules.where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.grand)) {
      if (number == rule.number) return const OfficialInvoiceAwardMatch(OfficialInvoiceAwardMatchKind.grand);
    }
    for (final rule in dataset.rules.where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.first)) {
      if (number == rule.number) return const OfficialInvoiceAwardMatch(OfficialInvoiceAwardMatchKind.first);
      for (var suffixLength = 7; suffixLength >= 3; suffixLength--) {
        if (number.endsWith(rule.number.substring(8 - suffixLength))) {
          final kind = switch (suffixLength) {
            7 => OfficialInvoiceAwardMatchKind.second,
            6 => OfficialInvoiceAwardMatchKind.third,
            5 => OfficialInvoiceAwardMatchKind.fourth,
            4 => OfficialInvoiceAwardMatchKind.fifth,
            _ => OfficialInvoiceAwardMatchKind.sixth,
          };
          return OfficialInvoiceAwardMatch(kind);
        }
      }
    }
    for (final rule in dataset.rules.where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.additionalSixth)) {
      if (number.endsWith(rule.number)) return const OfficialInvoiceAwardMatch(OfficialInvoiceAwardMatchKind.additionalSixth);
    }
    if (candidate.cloudExclusiveEligible) {
      for (final rule in dataset.rules.where((rule) => rule.kind == OfficialInvoiceAwardRuleKind.cloudExclusive)) {
        if (number == rule.number) return const OfficialInvoiceAwardMatch(OfficialInvoiceAwardMatchKind.cloudExclusive);
      }
    }
    return const OfficialInvoiceAwardMatch(OfficialInvoiceAwardMatchKind.notMatched);
  }
}
