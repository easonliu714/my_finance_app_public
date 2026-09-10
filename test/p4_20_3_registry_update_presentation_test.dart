import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_bounded_downloader.dart';
import 'package:my_finance_app/features/merchant/business_registry_update_service.dart';
import 'package:my_finance_app/features/merchant/business_registry_stream_validator.dart';
import 'package:my_finance_app/features/merchant/business_registry_transactional_stream_installer.dart';
import 'package:my_finance_app/features/profile/business_registry_update_presentation.dart';

void main() {
  test('download presentation exposes monotonic bounded telemetry', () {
    const progress = BusinessRegistryUpdateProgress(
      stage: BusinessRegistryUpdateStage.downloadingRegistry,
      download: BusinessRegistryDownloadProgress(
        downloadedBytes: 50 * 1024 * 1024,
        totalBytes: 100 * 1024 * 1024,
        attempt: 2,
        resumedFromBytes: 40 * 1024 * 1024,
        bytesPerSecond: 5 * 1024 * 1024,
        eta: Duration(seconds: 10),
      ),
    );

    expect(BusinessRegistryUpdatePresentation.progressFraction(progress), 0.5);
    final label = BusinessRegistryUpdatePresentation.stageLabel(progress);
    expect(label, contains('50.0 / 100.0 MB'));
    expect(label, contains('50.0%'));
    expect(label, contains('5.0 MB/s'));
    expect(label, contains('ETA 0:10'));
    expect(label, contains('第 2 次重試'));
    expect(label, contains('從 40.0 MB 續傳'));
  });

  test('validation presentation shows bytes speed percent and ETA', () {
    const progress = BusinessRegistryUpdateProgress(
      stage: BusinessRegistryUpdateStage.validatingRegistry,
      validation: BusinessRegistryValidationProgress(
        processedBytes: 400 * 1024 * 1024,
        totalBytes: 800 * 1024 * 1024,
        bytesPerSecond: 40 * 1024 * 1024,
        eta: Duration(seconds: 10),
      ),
    );

    expect(BusinessRegistryUpdatePresentation.progressFraction(progress), 0.5);
    final label = BusinessRegistryUpdatePresentation.stageLabel(progress);
    expect(label, contains('SHA-256 / stream'));
    expect(label, contains('400.0 / 800.0 MB'));
    expect(label, contains('50.0%'));
    expect(label, contains('40.0 MB/s'));
    expect(label, contains('ETA 0:10'));
  });

  test('install presentation shows entity throughput percent and ETA', () {
    const progress = BusinessRegistryUpdateProgress(
      stage: BusinessRegistryUpdateStage.installingRegistry,
      install: BusinessRegistryInstallProgress(
        processedEntities: 856432,
        totalEntities: 1712864,
        rowsPerSecond: 25000,
        eta: Duration(seconds: 34),
      ),
    );

    expect(BusinessRegistryUpdatePresentation.progressFraction(progress), 0.5);
    final label = BusinessRegistryUpdatePresentation.stageLabel(progress);
    expect(label, contains('安裝 V24 Registry'));
    expect(label, contains('856432 / 1712864 筆'));
    expect(label, contains('50.0%'));
    expect(label, contains('25000 筆/s'));
    expect(label, contains('ETA 0:34'));
  });
  test('stage presentation covers the full explicit update chain', () {
    for (final entry in <BusinessRegistryUpdateStage, String>{
      BusinessRegistryUpdateStage.readingManifest: 'manifest',
      BusinessRegistryUpdateStage.validatingRegistry: 'SHA-256',
      BusinessRegistryUpdateStage.installingRegistry: 'V24',
      BusinessRegistryUpdateStage.readingBackAuthority: 'authority',
      BusinessRegistryUpdateStage.complete: '已完成',
    }.entries) {
      final label = BusinessRegistryUpdatePresentation.stageLabel(
        BusinessRegistryUpdateProgress(stage: entry.key),
      );
      expect(label, contains(entry.value));
    }
  });

  test('transient error is actionable and redacts technical signed URL', () {
    const error = BusinessRegistryTransientDownloadException(
      retainedBytes: 24 * 1024 * 1024,
      cause: 'https://release-assets.githubusercontent.com/very/long/signed/url',
    );

    final message = BusinessRegistryUpdatePresentation.userFacingError(error);
    expect(message, contains('已保留 24.0 MB'));
    expect(message, contains('再次按更新續傳'));
    expect(message, isNot(contains('release-assets.githubusercontent.com')));
    expect(message, isNot(contains('https://')));
  });

  test('generic update failure preserves short LKG-oriented UX', () {
    final message = BusinessRegistryUpdatePresentation.userFacingError(
      StateError('https://release-assets.githubusercontent.com/secret'),
    );
    expect(message, contains('已保留上一個可用版本'));
    expect(message, isNot(contains('release-assets.githubusercontent.com')));
    expect(message, isNot(contains('https://')));
  });

  test('foreground hint documents restart-resume behavior', () {
    expect(
      BusinessRegistryUpdatePresentation.foregroundHint,
      contains('保持 App 前景'),
    );
    expect(
      BusinessRegistryUpdatePresentation.foregroundHint,
      contains('重新開啟後可續傳'),
    );
  });
}
