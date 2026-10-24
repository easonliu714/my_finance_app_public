import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_pdf_bounded_stream_decoder.dart';

void main() {
  test('passes through an unfiltered stream within the decoded bound', () {
    const decoder = CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 64,
      maxDecodedBytes: 64,
    );
    final source = utf8.encode('BT (BM23888900) Tj ET');

    expect(decoder.decode(bytes: source, filters: const <String>[]), source);
  });

  test('decodes FlateDecode through bounded chunked conversion', () {
    const decoder = CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 1024,
      maxDecodedBytes: 4096,
      inputChunkBytes: 7,
    );
    final clear = utf8.encode('BT [(BM) 0 (23888900)] TJ ET');
    final compressed = zlib.encode(clear);

    final decoded = decoder.decode(
      bytes: compressed,
      filters: const <String>['/FlateDecode'],
    );

    expect(decoded, clear);
  });

  test('accepts the PDF Fl abbreviation only as the single filter', () {
    const decoder = CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 1024,
      maxDecodedBytes: 4096,
    );
    final clear = utf8.encode('AB12345678');
    final compressed = zlib.encode(clear);

    expect(
      decoder.decode(bytes: compressed, filters: const <String>['Fl']),
      clear,
    );
  });

  test('fails closed on unsupported filters', () {
    const decoder = CloudAwardPdfBoundedStreamDecoder();

    expect(
      () => decoder.decode(
        bytes: const <int>[1, 2, 3],
        filters: const <String>['ASCII85Decode'],
      ),
      throwsA(
        isA<CloudAwardPdfBoundedStreamDecodeException>().having(
          (error) => error.code,
          'code',
          'CLOUD_AWARD_PDF_STREAM_UNSUPPORTED_FILTER_ASCII85DECODE',
        ),
      ),
    );
  });

  test('fails closed on multi-filter chains until explicitly admitted', () {
    const decoder = CloudAwardPdfBoundedStreamDecoder();

    expect(
      () => decoder.decode(
        bytes: const <int>[1, 2, 3],
        filters: const <String>['ASCII85Decode', 'FlateDecode'],
      ),
      throwsA(
        isA<CloudAwardPdfBoundedStreamDecodeException>().having(
          (error) => error.code,
          'code',
          'CLOUD_AWARD_PDF_STREAM_UNSUPPORTED_FILTER_CHAIN',
        ),
      ),
    );
  });

  test('rejects compressed input above the configured per-stream bound', () {
    const decoder = CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 3,
      maxDecodedBytes: 64,
    );

    expect(
      () => decoder.decode(
        bytes: const <int>[1, 2, 3, 4],
        filters: const <String>[],
      ),
      throwsA(
        isA<CloudAwardPdfBoundedStreamDecodeException>().having(
          (error) => error.code,
          'code',
          'CLOUD_AWARD_PDF_STREAM_COMPRESSED_LIMIT_EXCEEDED',
        ),
      ),
    );
  });

  test('stops Flate expansion when decoded bytes exceed the hard bound', () {
    const decoder = CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 4096,
      maxDecodedBytes: 128,
      inputChunkBytes: 5,
    );
    final compressed = zlib.encode(List<int>.filled(4096, 65));

    expect(
      () => decoder.decode(
        bytes: compressed,
        filters: const <String>['FlateDecode'],
      ),
      throwsA(
        isA<CloudAwardPdfBoundedStreamDecodeException>().having(
          (error) => error.code,
          'code',
          'CLOUD_AWARD_PDF_STREAM_DECODED_LIMIT_EXCEEDED',
        ),
      ),
    );
  });

  test('malformed Flate never falls back to an unbounded parser', () {
    const decoder = CloudAwardPdfBoundedStreamDecoder(
      maxCompressedBytes: 64,
      maxDecodedBytes: 64,
    );

    expect(
      () => decoder.decode(
        bytes: const <int>[0x78, 0x9c, 0x00, 0x01],
        filters: const <String>['FlateDecode'],
      ),
      throwsA(isA<CloudAwardPdfBoundedStreamDecodeException>()),
    );
  });
}
