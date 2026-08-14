const String officialPortalRootDomain = 'einvoice.nat.gov.tw';
const String officialPortalPrimaryHost = 'www.einvoice.nat.gov.tw';

/// Accepts only the Ministry of Finance e-invoice DNS boundary.
///
/// The exact apex and its HTTPS subdomains are allowed. Look-alike suffixes such
/// as `einvoice.nat.gov.tw.example.test` are rejected by the dot-boundary check.
bool isApprovedOfficialPortalHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == officialPortalRootDomain ||
      normalized.endsWith('.$officialPortalRootDomain');
}

bool isApprovedOfficialPortalHttpsUri(Uri uri) {
  return uri.scheme.toLowerCase() == 'https' &&
      uri.userInfo.isEmpty &&
      isApprovedOfficialPortalHost(uri.host);
}
