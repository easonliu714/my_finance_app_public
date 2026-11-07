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
      final normalizedFilterName = filter
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .toUpperCase();
      throw CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_UNSUPPORTED_FILTER_$normalizedFilterName',
      );
    }

    _validateZlibHeader(bytes);

    final output = _BoundedDecodedByteSink(maxBytes: maxDecodedBytes);
    try {
      final input = ZLibDecoder().startChunkedConversion(output);
      for (var offset = 0; offset < bytes.length; offset += inputChunkBytes) {
        final end = offset + inputChunkBytes < bytes.length
            ? offset + inputChunkBytes
            : bytes.length;
        input.add(bytes.sublist(offset, end));
      }
      input.close();

      final decoded = output.takeBytes();
      _validateAdler32(bytes: bytes, decoded: decoded);
      return decoded;
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

  void _validateZlibHeader(List<int> bytes) {
    // RFC 1950 requires CMF + FLG + at least a four-byte Adler-32 trailer.
    // Rejecting an incomplete envelope before decoding prevents Dart's
    // permissive chunked decoder from accepting a truncated stream.
    if (bytes.length < 6) {
      throw const CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_MALFORMED_FLATE',
      );
    }

    final cmf = bytes[0];
    final flg = bytes[1];
    final compressionMethod = cmf & 0x0f;
    final compressionInfo = cmf >> 4;
    final header = (cmf << 8) | flg;

    if (compressionMethod != 8 ||
        compressionInfo > 7 ||
        header % 31 != 0) {
      throw const CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_MALFORMED_FLATE',
      );
    }

    if ((flg & 0x20) != 0) {
      throw const CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_UNSUPPORTED_ZLIB_DICTIONARY',
      );
    }
  }

  void _validateAdler32({
    required List<int> bytes,
    required Uint8List decoded,
  }) {
    final trailerOffset = bytes.length - 4;
    final expected = (bytes[trailerOffset] << 24) |
        (bytes[trailerOffset + 1] << 16) |
        (bytes[trailerOffset + 2] << 8) |
        bytes[trailerOffset + 3];
    final actual = _adler32(decoded);

    if (actual != expected) {
      throw const CloudAwardPdfBoundedStreamDecodeException(
        'CLOUD_AWARD_PDF_STREAM_MALFORMED_FLATE',
      );
    }
  }

  int _adler32(List<int> bytes) {
    const modulus = 65521;
    var a = 1;
    var b = 0;

    for (final value in bytes) {
      a = (a + value) % modulus;
      b = (b + a) % modulus;
    }

    return (b << 16) | a;
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
