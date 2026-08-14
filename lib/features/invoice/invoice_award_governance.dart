enum InvoiceAwardMatchStatus {
  matched,
  partial,
  notMatched,
  invalid,
}

enum InvoiceAwardPrizeTier {
  special,
  grand,
  first,
  second,
  third,
  fourth,
  fifth,
  sixth,
  none,
}

class InvoiceAwardPeriod {
  const InvoiceAwardPeriod({
    required this.id,
    required this.year,
    required this.monthStart,
    required this.monthEnd,
  });

  final String id;
  final int year;
  final int monthStart;
  final int monthEnd;

  bool containsMonth(int month) => month >= monthStart && month <= monthEnd;
}

class InvoiceAwardNumberRule {
  const InvoiceAwardNumberRule({
    required this.id,
    required this.periodId,
    required this.number,
    required this.tier,
  });

  final String id;
  final String periodId;
  final String number;
  final InvoiceAwardPrizeTier tier;
}

class InvoiceAwardCandidate {
  const InvoiceAwardCandidate({
    required this.id,
    required this.invoiceNumber,
    required this.periodId,
    required this.sourceLabel,
  });

  final String id;
  final String invoiceNumber;
  final String periodId;
  final String sourceLabel;

  String get normalizedNumber => invoiceNumber.replaceAll(RegExp('[^0-9]'), '');
  bool get isValid => normalizedNumber.length == 8;
}

class InvoiceAwardMatchResult {
  const InvoiceAwardMatchResult({
    required this.candidate,
    required this.status,
    required this.tier,
    this.rule,
  });

  final InvoiceAwardCandidate candidate;
  final InvoiceAwardMatchStatus status;
  final InvoiceAwardPrizeTier tier;
  final InvoiceAwardNumberRule? rule;

  bool get needsReview => status == InvoiceAwardMatchStatus.matched || status == InvoiceAwardMatchStatus.partial || status == InvoiceAwardMatchStatus.invalid;
  bool get canCreateTransactionAutomatically => false;
}

class InvoiceAwardMatcher {
  const InvoiceAwardMatcher({
    required this.rules,
  });

  final List<InvoiceAwardNumberRule> rules;

  InvoiceAwardMatchResult match(InvoiceAwardCandidate candidate) {
    if (!candidate.isValid) {
      return InvoiceAwardMatchResult(
        candidate: candidate,
        status: InvoiceAwardMatchStatus.invalid,
        tier: InvoiceAwardPrizeTier.none,
      );
    }

    final periodRules = rules.where((rule) => rule.periodId == candidate.periodId);
    for (final rule in periodRules) {
      if (candidate.normalizedNumber == rule.number) {
        return InvoiceAwardMatchResult(
          candidate: candidate,
          status: InvoiceAwardMatchStatus.matched,
          tier: rule.tier,
          rule: rule,
        );
      }
    }

    for (final rule in periodRules) {
      if (candidate.normalizedNumber.endsWith(rule.number.substring(rule.number.length - 3))) {
        return InvoiceAwardMatchResult(
          candidate: candidate,
          status: InvoiceAwardMatchStatus.partial,
          tier: InvoiceAwardPrizeTier.sixth,
          rule: rule,
        );
      }
    }

    return InvoiceAwardMatchResult(
      candidate: candidate,
      status: InvoiceAwardMatchStatus.notMatched,
      tier: InvoiceAwardPrizeTier.none,
    );
  }
}

class CloudInvoicePortalLink {
  const CloudInvoicePortalLink({
    required this.title,
    required this.description,
    required this.officialUrl,
  });

  final String title;
  final String description;
  final String officialUrl;

  static const CloudInvoicePortalLink ministryOfFinance = CloudInvoicePortalLink(
    title: '財政部電子發票整合服務平台',
    description: '僅作為使用者自行前往官方平台查詢與設定的入口，不在 App 內保管憑證。',
    officialUrl: 'https://www.einvoice.nat.gov.tw/',
  );
}

class InvoiceAwardGovernanceCopy {
  const InvoiceAwardGovernanceCopy._();

  static const String reviewFirst = '對獎結果只進入待審核狀態，不會自動建立交易或領獎。';
  static const String noCredentialCustody = 'App 不保管官方平台帳密、憑證或一次性驗證碼。';
}
