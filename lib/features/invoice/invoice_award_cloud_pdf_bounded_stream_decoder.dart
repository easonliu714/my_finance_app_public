import 'dart:io';
import 'dart:typed_data';

class CloudAwardPdfBoundedStreamDecodeException implements Exception {
  const CloudAwardPdfBoundedStreamDecodeException(this.code);

  final String code;

  @override
  String toString() => code;
}

/// Bounded decoder scaffold for individually admitted PDF streams.
///
/// This class is intentionally not wired to cloud-award authority promotion.
/// It only provides a hard-bounded primitive that a future topology-specific
/// parser may use after the exact official PDF structure has been
/// characterized. Unsupported filter chains fail closed.
class CloudAwardPdfBoundedStreamDecoder {
  const CloudAwardPdfBoundedStreamDecoder({
    this.maxCompressedBytes = 2 * 1024 * 1024,
    this.maxDecodedBytes = 8 * 1024 * 1024,
    this.inputChunkBytes = 64 * 1024,
  })  : assert(maxCompressedBytes > 0),
        assert(maxDecodedBytes > 0),
        assert(inputChunkBytes > 0);

  final int maxCompressedBytes;
  final int maxDecodedBytes;
  final int inputChunkBytes;

  Uint8List decode({
    required List<int> bytes,
    required List<String> filters,
  }) {
    if (bytes.length > maxCompressedBytes) {
      throw const CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_COMPRESSED_LIMIT_EXCEEDED',
      );
    }

    final normalizedFilters = filters
        .map((value) => value.startsWith('/') ? value.substring(1) : value)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (normalizedFilters.isEmpty) {
      if (bytes.length > maxDecodedBytes) {
        throw const CloudAwardPdfBoundedStreamDecodeException(
          'CLOUD_AWARD_PDF_STREAM_DECODED_LIMIT_EXCEEDED',
        );
      }
      return Uint8List.fromList(bytes);
    }

    if (normalizedFilters.length != 1) {
      throw const CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_UNSUPPORTED_FILTER_CHAIN',
      );
    }

    final filter = normalizedFilters.single;
    if (filter != 'FlateDecode' && filter != 'Fl') {
      throw CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_UNSUPPORTED_FILTER_' +
            filter.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').toUpperCase(),
      );
    }

    final output = _BoundedDecodedByteSink(maxBytes: maxDecodedBytes);
    try {
      final input = const ZLibDecoder().startChunkedConversion(output);
      for (var offset = 0; offset < bytes.length; offset += inputChunkBytes) {
        final end = offset + inputChunkBytes < bytes.length
            ? offset + inputChunkBytes
            : bytes.length;
        input.add(bytes.sublist(offset, end));
      }
      input.close();
      return output.takeBytes();
    } on CloudAwardPdfBoundedStreamDecodeException {
      rethrow;
    } on FormatException {
      throw const CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_MALFORMED_FLATE',
      );
    } catch (_) {
      throw const CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_DECODE_FAILED',
      );
    }
  }
}

class _BoundedDecodedByteSink implements Sink<List<int>> {
  _BoundedDecodedByteSink({required this.maxBytes});

  final int maxBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _length = 0;
  bool _closed = false;

  @override
  void add(List<int> data) {
    if (_closed) {
      throw StateError('CLOUD_AWARD_PDF_STREAM_SINK_CLOSED');
    }
    if (_length + data.length > maxBytes) {
      throw const CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_DECODED_LIMIT_EXCEEDED',
      );
    }
    _builder.add(data);
    _length += data.length;
  }

  @override
  void close() {
    _closed = true;
  }

  Uint8List takeBytes() => _builder.takeBytes();
}
