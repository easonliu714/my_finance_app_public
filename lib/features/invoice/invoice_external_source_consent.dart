enum InvoiceExternalSourceCredentialCustody {
  none,
  sessionOnly,
  encryptedToken,
  unsupported,
}

class InvoiceExternalSourceConsent {
  const InvoiceExternalSourceConsent({
    required this.networkAccessAcknowledged,
    required this.externalDataAcknowledged,
    required this.reviewGateAcknowledged,
    required this.revokeDeleteAcknowledged,
    this.credentialCustody = InvoiceExternalSourceCredentialCustody.none,
    this.syncFrequencyAcknowledged = false,
    this.backgroundSyncEnabled = false,
  });

  final bool networkAccessAcknowledged;
  final bool externalDataAcknowledged;
  final bool reviewGateAcknowledged;
  final bool revokeDeleteAcknowledged;
  final bool syncFrequencyAcknowledged;
  final bool backgroundSyncEnabled;
  final InvoiceExternalSourceCredentialCustody credentialCustody;

  bool get leavesDevice => networkAccessAcknowledged;

  bool get storesCredential => credentialCustody != InvoiceExternalSourceCredentialCustody.none;

  bool get isReady {
    if (!networkAccessAcknowledged) return false;
    if (!externalDataAcknowledged) return false;
    if (!reviewGateAcknowledged) return false;
    if (!revokeDeleteAcknowledged) return false;
    if (backgroundSyncEnabled && !syncFrequencyAcknowledged) return false;
    if (credentialCustody != InvoiceExternalSourceCredentialCustody.none) return false;
    return true;
  }

  List<String> missingGateMessages() {
    final messages = <String>[];
    if (!networkAccessAcknowledged) messages.add(InvoiceExternalSourceConsentCopy.networkGate);
    if (!externalDataAcknowledged) messages.add(InvoiceExternalSourceConsentCopy.externalDataGate);
    if (!reviewGateAcknowledged) messages.add(InvoiceExternalSourceConsentCopy.reviewGate);
    if (!revokeDeleteAcknowledged) messages.add(InvoiceExternalSourceConsentCopy.revokeDeleteGate);
    if (backgroundSyncEnabled && !syncFrequencyAcknowledged) messages.add(InvoiceExternalSourceConsentCopy.syncFrequencyGate);
    if (credentialCustody != InvoiceExternalSourceCredentialCustody.none) messages.add(InvoiceExternalSourceConsentCopy.credentialCustodyBlockedGate);
    return List<String>.unmodifiable(messages);
  }

  InvoiceExternalSourceConsent copyWith({
    bool? networkAccessAcknowledged,
    bool? externalDataAcknowledged,
    bool? reviewGateAcknowledged,
    bool? revokeDeleteAcknowledged,
    bool? syncFrequencyAcknowledged,
    bool? backgroundSyncEnabled,
    InvoiceExternalSourceCredentialCustody? credentialCustody,
  }) {
    return InvoiceExternalSourceConsent(
      networkAccessAcknowledged: networkAccessAcknowledged ?? this.networkAccessAcknowledged,
      externalDataAcknowledged: externalDataAcknowledged ?? this.externalDataAcknowledged,
      reviewGateAcknowledged: reviewGateAcknowledged ?? this.reviewGateAcknowledged,
      revokeDeleteAcknowledged: revokeDeleteAcknowledged ?? this.revokeDeleteAcknowledged,
      syncFrequencyAcknowledged: syncFrequencyAcknowledged ?? this.syncFrequencyAcknowledged,
      backgroundSyncEnabled: backgroundSyncEnabled ?? this.backgroundSyncEnabled,
      credentialCustody: credentialCustody ?? this.credentialCustody,
    );
  }
}

class InvoiceExternalSourceConsentCopy {
  const InvoiceExternalSourceConsentCopy._();

  static const String networkGate = '我了解此功能會連線外部電子發票服務，資料可能離開本機。';
  static const String externalDataGate = '我了解外部服務可能回傳發票號碼、日期、金額、賣方資訊與品項資料。';
  static const String reviewGate = '我了解外部取得的資料只會先成為草稿或候選資料，需再次確認才會建立正式交易。';
  static const String revokeDeleteGate = '我了解後續需提供刪除本機資料與撤銷授權的入口。';
  static const String syncFrequencyGate = '我了解若啟用同步，必須明確選擇同步頻率並可隨時停用。';
  static const String credentialCustodyBlockedGate = '目前不保存載具帳密、驗證碼或可長期重放的 token。';

  static const List<String> requiredDisclosure = <String>[
    networkGate,
    externalDataGate,
    reviewGate,
    revokeDeleteGate,
    credentialCustodyBlockedGate,
  ];
}
