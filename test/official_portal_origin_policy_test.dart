import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/official_portal_origin_policy.dart';

void main() {
  test('accepts the official apex and HTTPS subdomains', () {
    expect(isApprovedOfficialPortalHost('einvoice.nat.gov.tw'), isTrue);
    expect(isApprovedOfficialPortalHost('www.einvoice.nat.gov.tw'), isTrue);
    expect(isApprovedOfficialPortalHost('download.einvoice.nat.gov.tw'), isTrue);
    expect(
      isApprovedOfficialPortalHttpsUri(
        Uri.parse('https://download.einvoice.nat.gov.tw/export.csv'),
      ),
      isTrue,
    );
  });

  test('rejects look-alike suffixes, userinfo, and non-HTTPS URLs', () {
    expect(
      isApprovedOfficialPortalHost('einvoice.nat.gov.tw.example.test'),
      isFalse,
    );
    expect(
      isApprovedOfficialPortalHost('fakeeinvoice.nat.gov.tw.example.test'),
      isFalse,
    );
    expect(
      isApprovedOfficialPortalHttpsUri(
        Uri.parse('https://user@www.einvoice.nat.gov.tw/export.csv'),
      ),
      isFalse,
    );
    expect(
      isApprovedOfficialPortalHttpsUri(
        Uri.parse('http://www.einvoice.nat.gov.tw/export.csv'),
      ),
      isFalse,
    );
  });
}
