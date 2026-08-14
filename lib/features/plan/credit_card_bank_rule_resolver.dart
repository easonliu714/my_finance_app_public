import '../account/account_record.dart';
import 'credit_card_bank_rule_profile.dart';

class CreditCardResolvedBankRule {
  const CreditCardResolvedBankRule({
    required this.profile,
    required this.source,
  });

  final CreditCardBankRuleProfile profile;
  final CreditCardBankRuleSource source;

  bool get isCustom => source == CreditCardBankRuleSource.custom;
  String get sourceLabel => isCustom ? '自訂銀行規則' : '系統預設估算';
}

enum CreditCardBankRuleSource { systemDefault, custom }

CreditCardResolvedBankRule resolveCreditCardBankRule({
  required AccountRecord card,
  required String? assignedProfileId,
  required List<CreditCardBankRuleProfile> profiles,
}) {
  CreditCardBankRuleProfile? matchedProfile;
  if (assignedProfileId != null) {
    for (final profile in profiles) {
      if (profile.id == assignedProfileId) {
        matchedProfile = profile;
        break;
      }
    }
  }

  if (matchedProfile == null) {
    return CreditCardResolvedBankRule(
      profile: CreditCardBankRuleProfile.defaultEstimate(card.currency),
      source: CreditCardBankRuleSource.systemDefault,
    );
  }
  return CreditCardResolvedBankRule(
    profile: matchedProfile,
    source: CreditCardBankRuleSource.custom,
  );
}
