import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/merchant_identity_resolution_policy.dart';

void main() {
  const policy = MerchantIdentityResolutionPolicy();

  test('registry cannot promote a non-authoritative seller identifier', () {
    final decision = policy.evaluate(
      sellerIdentifier: '60744698',
      sellerIdentifierAuthoritative: false,
      literalMerchantText: '全家便利商店 板橋店',
      officialRegistryLegalName: '某某股份有限公司',
    );

    expect(decision.registryLookupAllowed, isFalse);
    expect(decision.officialLegalNameSuggestion, isEmpty);
    expect(decision.formalMerchantName, isEmpty);
    expect(decision.literalMerchantText, '全家便利商店 板橋店');
    expect(
      decision.reason,
      MerchantIdentityResolutionReason.sellerIdentifierNotAuthoritative,
    );
  });

  test('official legal name remains a suggestion and does not replace literal merchant text', () {
    final decision = policy.evaluate(
      sellerIdentifier: '60744698',
      sellerIdentifierAuthoritative: true,
      literalMerchantText: '全家便利商店 板橋店',
      officialRegistryLegalName: '日翊文化行銷股份有限公司',
    );

    expect(decision.registryLookupAllowed, isTrue);
    expect(decision.officialLegalNameSuggestion, '日翊文化行銷股份有限公司');
    expect(decision.literalMerchantText, '全家便利商店 板橋店');
    expect(decision.formalMerchantName, isEmpty);
    expect(decision.requiresBrandConfirmation, isTrue);
    expect(
      decision.reason,
      MerchantIdentityResolutionReason.registryLegalNameNeedsBrandConfirmation,
    );
  });

  test('existing confirmed brand link may be reused without legal-name overwrite', () {
    final decision = policy.evaluate(
      sellerIdentifier: '60744698',
      sellerIdentifierAuthoritative: true,
      literalMerchantText: '全家 板橋新站店',
      officialRegistryLegalName: '某加盟商有限公司',
      existingConfirmedBrandName: '全家便利商店',
    );

    expect(decision.registryLookupAllowed, isTrue);
    expect(decision.formalMerchantName, '全家便利商店');
    expect(decision.officialLegalNameSuggestion, '某加盟商有限公司');
    expect(decision.requiresBrandConfirmation, isFalse);
    expect(decision.literalMerchantText, '全家 板橋新站店');
    expect(decision.reason, MerchantIdentityResolutionReason.confirmedBrandLink);
  });

  test('authoritative unseen seller remains review-required when registry misses', () {
    final decision = policy.evaluate(
      sellerIdentifier: '60744698',
      sellerIdentifierAuthoritative: true,
      literalMerchantText: '新商家',
    );

    expect(decision.registryLookupAllowed, isTrue);
    expect(decision.formalMerchantName, isEmpty);
    expect(decision.requiresBrandConfirmation, isTrue);
    expect(
      decision.reason,
      MerchantIdentityResolutionReason.authoritativeSellerNeedsReview,
    );
  });

  test('negative lookup identity is scoped to seller and registry version', () {
    expect(
      businessRegistryNegativeLookupKey(
        sellerIdentifier: '6074-4698',
        snapshotVersion: '2026-08-a',
      ),
      '60744698|2026-08-a',
    );
    expect(
      businessRegistryNegativeLookupKey(
        sellerIdentifier: '60744698',
        snapshotVersion: '2026-09-a',
      ),
      isNot('60744698|2026-08-a'),
    );
  });
}
