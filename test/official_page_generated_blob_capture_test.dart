import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/lab/official_page_generated_blob_capture.dart';

void main() {
  test('capture script stores only bounded Blob references', () {
    final script = buildOfficialPageGeneratedBlobCaptureScript();

    expect(script, contains('createObjectURL'));
    expect(script, contains('object instanceof target.Blob'));
    expect(script, contains('object.size <= maximumBytes'));
    expect(script, contains('store.set(objectUrl, object)'));
    expect(script, contains('retentionMs = 60000'));
    expect(script, isNot(contains('document.cookie')));
    expect(script, isNot(contains('innerHTML')));
    expect(script, isNot(contains('outerHTML')));
  });

  test('read script prefers captured Blob and uses bounded chunks', () {
    final script = buildOfficialPageGeneratedBlobReadScript(
      blobUri: Uri.parse('blob:https://www.einvoice.nat.gov.tw/test-id'),
      handlerName: 'handler',
      fileName: 'invoice.csv',
    );

    expect(script, contains('findCapturedBlob'));
    expect(script, contains('CSV_BLOB_NOT_CAPTURED'));
    expect(script, contains('blob.arrayBuffer()'));
    expect(script, contains('chunkSize = 65536'));
    expect(script, contains('CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED'));
    expect(script, isNot(contains('document.cookie')));
    expect(script, isNot(contains('localStorage')));
    expect(script, isNot(contains('sessionStorage')));
  });
}
