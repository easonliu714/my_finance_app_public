import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'taiwan_business_calendar_csv_import.dart';
import 'taiwan_business_calendar_official_116_stage.dart';
import 'taiwan_business_calendar_pinned_116_install.dart';

/// B2.14b: explicit manual official-source check, never installation.
/// No background network, SQLite/account write, inferred 2026 holidays,
/// revision promotion or persisted check receipt.
class TaiwanBusinessCalendarAnnualSourceCheck {
  const TaiwanBusinessCalendarAnnualSourceCheck({this.readPinnedCsv});

  /// Test seam only; production always requests the exact pinned DGPA URL.
  final Future<Uint8List> Function()? readPinnedCsv;

  Future<TaiwanBusinessCalendarAnnualSourceResult> check() async {
    final bytes = await (readPinnedCsv ?? _downloadPinned116)();
    final staged =
        await const TaiwanBusinessCalendarOfficial116Stage().verify(bytes);
    // Return metadata only; do not retain or publish original source bytes.
    return TaiwanBusinessCalendarAnnualSourceResult(
      sha256: staged.rawSha256,
      days: staged.days.length,
      holidays: staged.holidayCount,
    );
  }

  // B2.14e: Stream.timeout only bounds idle gaps, not total download time.
  // A slow-drip server could otherwise keep a manual HTTPS check alive
  // indefinitely. Enforce an independent deadline and cancel the stream.
  // This remains read-only: no calendar or finance SQLite write.
  static Future<Uint8List> readBoundedOfficialCsvStream(
    Stream<List<int>> source, {
    Duration maxElapsed = const Duration(seconds: 45),
  }) async {
    if (maxElapsed <= Duration.zero) {
      throw ArgumentError.value(maxElapsed, 'maxElapsed');
    }
    final bytes = BytesBuilder(copy: false);
    final completed = Completer<Uint8List>();
    final subscription = source.listen(
      (chunk) {
        if (completed.isCompleted) return;
        if (bytes.length + chunk.length >
            TaiwanBusinessCalendarOfficialCsvCodec.maxCsvBytes) {
          completed.completeError(
            const FormatException('Official CSV response exceeds cap.'),
          );
          return;
        }
        bytes.add(chunk);
      },
      onError: (Object error, StackTrace stack) {
        if (!completed.isCompleted) completed.completeError(error, stack);
      },
      onDone: () {
        if (!completed.isCompleted) completed.complete(bytes.takeBytes());
      },
    );
    final deadline = Timer(maxElapsed, () {
      if (!completed.isCompleted) {
        completed.completeError(
          TimeoutException('Official CSV total download deadline exceeded.'),
        );
      }
    });
    try {
      return await completed.future;
    } finally {
      deadline.cancel();
      await subscription.cancel();
    }
  }

  static Future<Uint8List> _downloadPinned116() async {
    final uri = Uri.parse(TaiwanBusinessCalendarPinned116Installer.sourceUrl);
    if (uri.scheme != 'https' ||
        uri.host != 'www.dgpa.gov.tw' ||
        uri.path != '/FileConversion' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('Pinned official source origin invalid.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(uri).timeout(
        const Duration(seconds: 15),
      );
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/csv,application/octet-stream',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok ||
          response.redirects.isNotEmpty ||
          response.contentLength >
              TaiwanBusinessCalendarOfficialCsvCodec.maxCsvBytes) {
        throw const FormatException(
          'Official CSV response rejected before parsing.',
        );
      }
      return readBoundedOfficialCsvStream(
        response.timeout(const Duration(seconds: 30)),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class TaiwanBusinessCalendarAnnualSourceResult {
  const TaiwanBusinessCalendarAnnualSourceResult({
    required this.sha256,
    required this.days,
    required this.holidays,
  });

  final String sha256;
  final int days;
  final int holidays;
}
