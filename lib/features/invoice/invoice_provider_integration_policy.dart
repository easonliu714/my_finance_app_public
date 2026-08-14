enum InvoiceProviderIntegrationMode {
  officialPortalHandoff,
  userImportedFile,
  copiedDataImport,
  sessionOnlyAuthorization,
  storedCredential,
  longLivedToken,
  embeddedWebViewLogin,
  backgroundSync,
}

enum InvoiceProviderPolicyDecision {
  allowed,
  blocked,
  requiresFutureSecurityReview,
}

class InvoiceProviderIntegrationPolicyResult {
  const InvoiceProviderIntegrationPolicyResult({
    required this.mode,
    required this.decision,
    required this.reason,
    this.requiresReviewGate = true,
    this.allowsCredentialCustody = false,
    this.allowsBackgroundSync = false,
    this.allowsAutomaticTransactionCreation = false,
  });

  final InvoiceProviderIntegrationMode mode;
  final InvoiceProviderPolicyDecision decision;
  final String reason;
  final bool requiresReviewGate;
  final bool allowsCredentialCustody;
  final bool allowsBackgroundSync;
  final bool allowsAutomaticTransactionCreation;

  bool get isAllowed => decision == InvoiceProviderPolicyDecision.allowed;
  bool get isBlocked => decision == InvoiceProviderPolicyDecision.blocked;
  bool get requiresFutureReview => decision == InvoiceProviderPolicyDecision.requiresFutureSecurityReview;
}

class InvoiceProviderIntegrationPolicyService {
  const InvoiceProviderIntegrationPolicyService();

  InvoiceProviderIntegrationPolicyResult evaluate(InvoiceProviderIntegrationMode mode) {
    switch (mode) {
      case InvoiceProviderIntegrationMode.officialPortalHandoff:
        return const InvoiceProviderIntegrationPolicyResult(
          mode: InvoiceProviderIntegrationMode.officialPortalHandoff,
          decision: InvoiceProviderPolicyDecision.allowed,
          reason: InvoiceProviderIntegrationPolicyCopy.officialPortalHandoffAllowed,
        );
      case InvoiceProviderIntegrationMode.userImportedFile:
        return const InvoiceProviderIntegrationPolicyResult(
          mode: InvoiceProviderIntegrationMode.userImportedFile,
          decision: InvoiceProviderPolicyDecision.allowed,
          reason: InvoiceProviderIntegrationPolicyCopy.userImportAllowed,
        );
      case InvoiceProviderIntegrationMode.copiedDataImport:
        return const InvoiceProviderIntegrationPolicyResult(
          mode: InvoiceProviderIntegrationMode.copiedDataImport,
          decision: InvoiceProviderPolicyDecision.allowed,
          reason: InvoiceProviderIntegrationPolicyCopy.userImportAllowed,
        );
      case InvoiceProviderIntegrationMode.sessionOnlyAuthorization:
        return const InvoiceProviderIntegrationPolicyResult(
          mode: InvoiceProviderIntegrationMode.sessionOnlyAuthorization,
          decision: InvoiceProviderPolicyDecision.requiresFutureSecurityReview,
          reason: InvoiceProviderIntegrationPolicyCopy.sessionOnlyRequiresReview,
        );
      case InvoiceProviderIntegrationMode.storedCredential:
        return const InvoiceProviderIntegrationPolicyResult(
          mode: InvoiceProviderIntegrationMode.storedCredential,
          decision: InvoiceProviderPolicyDecision.blocked,
          reason: InvoiceProviderIntegrationPolicyCopy.credentialCustodyBlocked,
        );
      case InvoiceProviderIntegrationMode.longLivedToken:
        return const InvoiceProviderIntegrationPolicyResult(
          mode: InvoiceProviderIntegrationMode.longLivedToken,
          decision: InvoiceProviderPolicyDecision.blocked,
          reason: InvoiceProviderIntegrationPolicyCopy.credentialCustodyBlocked,
        );
      case InvoiceProviderIntegrationMode.embeddedWebViewLogin:
        return const InvoiceProviderIntegrationPolicyResult(
          mode: InvoiceProviderIntegrationMode.embeddedWebViewLogin,
          decision: InvoiceProviderPolicyDecision.blocked,
          reason: InvoiceProviderIntegrationPolicyCopy.embeddedLoginBlocked,
        );
      case InvoiceProviderIntegrationMode.backgroundSync:
        return const InvoiceProviderIntegrationPolicyResult(
          mode: InvoiceProviderIntegrationMode.backgroundSync,
          decision: InvoiceProviderPolicyDecision.blocked,
          reason: InvoiceProviderIntegrationPolicyCopy.backgroundSyncBlocked,
        );
    }
  }

  List<InvoiceProviderIntegrationPolicyResult> evaluateAll() {
    return InvoiceProviderIntegrationMode.values.map(evaluate).toList(growable: false);
  }
}

class InvoiceProviderIntegrationPolicyCopy {
  const InvoiceProviderIntegrationPolicyCopy._();

  static const String officialPortalHandoffAllowed = '官方入口交接可作為使用者主動離開 App 的安全入口，但取得資料仍需明確匯入並進入候選檢查。';
  static const String userImportAllowed = '使用者主動匯入檔案或貼上資料可以進入候選清單，但不可直接建立正式交易。';
  static const String sessionOnlyRequiresReview = 'session-only 授權仍涉及外部登入與資料回傳，需另行安全審查與撤銷/刪除設計後才可實作。';
  static const String credentialCustodyBlocked = '預設不保存載具帳密、驗證碼、refresh token 或可長期重放的 token。';
  static const String embeddedLoginBlocked = '預設不在 App 內嵌 WebView 執行載具登入，避免混淆授權邊界與 credential custody。';
  static const String backgroundSyncBlocked = '預設不啟動發票背景同步；同步頻率、撤銷、刪除與風險揭露需另行治理。';
  static const String reviewGateRequired = '所有外部發票資料都必須先進入 staging / draft review，不可自動建立正式交易。';

  static const List<String> defaultGuardrails = <String>[
    credentialCustodyBlocked,
    backgroundSyncBlocked,
    reviewGateRequired,
  ];
}
