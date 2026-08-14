import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/image_staging_preview.dart';

void main() {
  test('default source choices expose camera gallery and manual placeholders', () {
    const state = ImageStagingPreviewState();

    expect(state.sourceChoices.length, 3);
    expect(state.sourceChoices.map((choice) => choice.option), <ImageSourceOption>[
      ImageSourceOption.camera,
      ImageSourceOption.gallery,
      ImageSourceOption.manual,
    ]);
    expect(state.sourceChoices.where((choice) => choice.enabled).single.option, ImageSourceOption.manual);
  });

  test('preview state counts pending and ready items', () {
    const state = ImageStagingPreviewState(
      items: <ImageStagingPreviewItem>[
        ImageStagingPreviewItem(
          id: 'pending-invoice',
          kind: ImageStagingPreviewKind.invoice,
          status: ImageStagingPreviewStatus.pending,
          sourceOption: ImageSourceOption.camera,
          title: '發票影像',
          summary: '等待處理',
        ),
        ImageStagingPreviewItem(
          id: 'ready-product',
          kind: ImageStagingPreviewKind.product,
          status: ImageStagingPreviewStatus.ready,
          sourceOption: ImageSourceOption.gallery,
          title: '商品影像',
          summary: '待人工確認',
        ),
      ],
    );

    expect(state.isEmpty, isFalse);
    expect(state.pendingCount, 1);
    expect(state.readyCount, 1);
  });

  test('ready item can review and convert only after explicit action', () {
    const item = ImageStagingPreviewItem(
      id: 'ready-invoice',
      kind: ImageStagingPreviewKind.invoice,
      status: ImageStagingPreviewStatus.ready,
      sourceOption: ImageSourceOption.gallery,
      title: '電子發票影像',
      summary: '候選資料已建立',
    );

    expect(item.canReview, isTrue);
    expect(item.canConvert, isTrue);
    expect(item.isTerminal, isFalse);
  });

  test('rejected and converted items are terminal', () {
    const rejected = ImageStagingPreviewItem(
      id: 'rejected',
      kind: ImageStagingPreviewKind.invoice,
      status: ImageStagingPreviewStatus.rejected,
      sourceOption: ImageSourceOption.camera,
      title: '退回項目',
      summary: '人工退回',
    );
    const converted = ImageStagingPreviewItem(
      id: 'converted',
      kind: ImageStagingPreviewKind.product,
      status: ImageStagingPreviewStatus.converted,
      sourceOption: ImageSourceOption.gallery,
      title: '已轉換項目',
      summary: '已建立草稿候選',
    );

    expect(rejected.isTerminal, isTrue);
    expect(converted.isTerminal, isTrue);
    expect(rejected.canConvert, isFalse);
    expect(converted.canReview, isFalse);
  });
}
