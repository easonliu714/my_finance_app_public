import 'invoice_external_source_consent.dart';

class InvoiceOfficialPortalHandoffError implements Exception {
  const InvoiceOfficialPortalHandoffError(this.message);

  final String message;

  @override
  String toString() => message;
}

class InvoiceOfficialPortalHandoffTarget {
  const InvoiceOfficialPortalHandoffTarget({
    required this.name,
    required this.uri,
    this.description = '',
  });

  final String name;
  final Uri uri;
  final String description;

  bool get isHttps => uri.scheme.toLowerCase() == 'https';
}

class InvoiceOfficialPortalHandoffRequest {
  const InvoiceOfficialPortalHandoffRequest({
    required this.id,
    required this.target,
    required this.createdAt,
    this.disclosure = InvoiceOfficialPortalHandoffCopy.defaultDisclosure,
  });

  final String id;
  final InvoiceOfficialPortalHandoffTarget target;
  final DateTime createdAt;
  final String disclosure;

  bool get leavesApp => true;
  bool get storesCredential => false;
  bool get startsBackgroundSync => false;
  bool get createsDraftOrTransactionAutomatically => false;
}

class InvoiceOfficialPortalHandoffService {
  const InvoiceOfficialPortalHandoffService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  InvoiceOfficialPortalHandoffRequest createRequest({
    required String id,
    required InvoiceExternalSourceConsent consent,
    required InvoiceOfficialPortalHandoffTarget target,
  }) {
    if (!consent.isReady) {
      throw const InvoiceOfficialPortalHandoffError('Official portal handoff requires completed external-source consent gates.');
    }
    if (!target.isHttps) {
      throw const InvoiceOfficialPortalHandoffError('Official portal handoff target must use HTTPS.');
    }
    return InvoiceOfficialPortalHandoffRequest(id: id, target: target, createdAt: _clock().toUtc());
  }
}

class InvoiceOfficialPortalHandoffCopy {
  const InvoiceOfficialPortalHandoffCopy._();

  static const String defaultDisclosure = '即將離開 App 前往外部電子發票入口。App 不會保存載具帳密、驗證碼或 token；取得的資料需由你返回 App 後明確匯入或進入候選清單，再經確認才會建立草稿或交易。';
  static const String noCredentialCustody = '不保存載具帳密、驗證碼或可長期重放的 token。';
  static const String noBackgroundSync = '不啟動背景同步；每次交接都必須由使用者主動操作。';
  static const String reviewRequired = '外部取得的發票資料必須先進入候選或草稿檢查，不會自動建立正式交易。';

  static const List<String> requiredDisclosure = <String>[
    defaultDisclosure,
    noCredentialCustody,
    noBackgroundSync,
    reviewRequired,
  ];
}
