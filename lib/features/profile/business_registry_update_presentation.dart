import '../merchant/business_registry_bounded_downloader.dart';
import '../merchant/business_registry_update_service.dart';

/// Pure presentation helpers for the explicit Registry update surface.
///
/// This layer deliberately accepts already-bounded update telemetry and never
/// performs network access. It also prevents transport exceptions from leaking
/// long signed GitHub asset URLs into the user-visible UI.
class BusinessRegistryUpdatePresentation {
  const BusinessRegistryUpdatePresentation._();

  static const String foregroundHint =
      '更新期間建議保持 App 前景；若手動鎖屏或系統中止，重新開啟後可續傳。';

  static String stageLabel(BusinessRegistryUpdateProgress progress) {
    switch (progress.stage) {
      case BusinessRegistryUpdateStage.readingManifest:
        return '正在讀取 Registry manifest…';
      case BusinessRegistryUpdateStage.downloadingRegistry:
        return _downloadLabel(progress.download);
      case BusinessRegistryUpdateStage.validatingRegistry:
        return '下載完成，正在驗證 SHA-256 與 Registry stream…';
      case BusinessRegistryUpdateStage.installingRegistry:
        return '驗證完成，正在安裝 V24 Registry…';
      case BusinessRegistryUpdateStage.readingBackAuthority:
        return '安裝完成，正在確認版本與 authority…';
      case BusinessRegistryUpdateStage.complete:
        return 'Registry 更新流程已完成。';
    }
  }

  static double? progressFraction(BusinessRegistryUpdateProgress progress) {
    final download = progress.download;
    if (progress.stage != BusinessRegistryUpdateStage.downloadingRegistry ||
        download == null ||
        download.totalBytes <= 0) {
      return null;
    }
    return download.fraction;
  }

  static String userFacingError(Object error) {
    if (error is BusinessRegistryTransientDownloadException) {
      final retained = _formatMegabytes(error.retainedBytes);
      return '下載連線中斷；已保留 $retained MB，可再次按更新續傳。';
    }
    return '公司行號資料更新失敗；已保留上一個可用版本。請稍後再次按更新。';
  }

  static String _downloadLabel(BusinessRegistryDownloadProgress? progress) {
    if (progress == null) return '正在下載 Registry…';

    final downloaded = _formatMegabytes(progress.downloadedBytes);
    final total = _formatMegabytes(progress.totalBytes);
    final percent = (progress.fraction * 100).clamp(0, 100).toStringAsFixed(1);
    final speed = progress.bytesPerSecond > 0
        ? '${_formatMegabytes(progress.bytesPerSecond) } MB/s'
        : '計算中';
    final eta = _formatEta(progress.eta);
    final retry = progress.attempt > 1 ? '；第 ${progress.attempt} 次重試' : '';
    final resumed = progress.resumedFromBytes > 0
        ? '；從 ${_formatMegabytes(progress.resumedFromBytes)} MB 續傳'
        : '';

    return '下載 Registry：$downloaded / $total MB（$percent%）'
        '；$speed；ETA $eta$retry$resumed';
  }

  static String _formatMegabytes(num bytes) =>
      (bytes / (1024 * 1024)).clamp(0, double.infinity).toStringAsFixed(1);

  static String _formatEta(Duration? eta) {
    if (eta == null) return '計算中';
    final safe = eta.isNegative ? Duration.zero : eta;
    if (safe.inHours > 0) {
      final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
      return '${safe.inHours}:$minutes';
    }
    final minutes = safe.inMinutes;
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
