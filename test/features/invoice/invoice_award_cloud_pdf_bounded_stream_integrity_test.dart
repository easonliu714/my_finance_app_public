import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_bounded_stream_decoder.dart';

void main() {
  test('fails closed when Flate payload has a corrupted Adler-32 trailer', () {
    const decoder = CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 1024,
      maxDecodedBytes: 4096,
      inputChunkBytes: 7,
    );
    final compressed = zlib.encode(
      utf8.encode('BT [(BM) 0 (23888900)] TJ ET'),
    );

    // Keep the zlib header and deflate payload intact while corrupting only
    // the integrity trailer. The bounded decoder must not promote decoded
    // bytes unless the RFC 1950 Adler-32 envelope validates.
    compressed[compressed.length - 1] ^= 0x01;

    expect(
      () => decoder.decode(
        bytes: compressed,
        filters: const <String>['/FlateDecode'],
      ),
      throwsA(
        isA<CloudAwardPdfBoundedStreamDecodeException>().having(
          (error) => error.code,
          'code',
          'CLOUD_AWARD_PDF_STREAM_MALFORMED_FLATE',
        ),
      ),
    );
  });

  test('fails closed when Flate header requests a preset dictionary', () {
    const decoder = CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 64,
      maxDecodedBytes: 64,
    );

    // 0x78 0x20 is a valid RFC 1950 CMF/FLG pair with FDICT set. The
    // production path deliberately does not admit external dictionaries.
    expect(
      () => decoder.decode(
        bytes: const <int>[0x78, 0x20, 0, 0, 0, 0],
        filters: const <String>['/FlateDecode'],
      ),
      throwsA(
        isA<CloudAwardPdfBoundedStreamDecodeException>().having(
          (error) => error.code,
          'code',
          'CLOUD_AWARD_PDF_STREAM_UNSUPPORTED_ZLIB_DICTIONARY',
        ),
      ),
    );
  });
}
