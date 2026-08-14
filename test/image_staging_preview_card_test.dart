import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/image_staging_preview.dart';
import 'package:my_finance_app/features/invoice/image_staging_preview_card.dart';

void main() {
  testWidgets('ImageStagingPreviewCard renders source choices and empty review-first state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImageStagingPreviewCard(),
        ),
      ),
    );

    expect(find.byKey(ImageStagingPreviewCard.cardKey), findsOneWidget);
    expect(find.byKey(ImageStagingPreviewCard.sourceChoicesKey), findsOneWidget);
    expect(find.byKey(ImageStagingPreviewCard.cameraChoiceKey), findsOneWidget);
    expect(find.byKey(ImageStagingPreviewCard.galleryChoiceKey), findsOneWidget);
    expect(find.byKey(ImageStagingPreviewCard.manualChoiceKey), findsOneWidget);
    expect(find.text('影像輔助記帳'), findsOneWidget);
    expect(find.text('支援發票與商品影像的 staging preview；正式寫入前必須人工確認。'), findsOneWidget);
    expect(find.text('所有影像結果都只會進入待審核清單，不會自動建立交易。'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('從相簿選擇'), findsOneWidget);
    expect(find.text('手動建立'), findsOneWidget);
    expect(find.text('待審核：0，處理中：0'), findsOneWidget);
    expect(find.text('目前沒有待審核影像項目。'), findsOneWidget);
  });

  testWidgets('ImageStagingPreviewCard renders pending and ready preview items', (tester) async {
    const state = ImageStagingPreviewState(
      items: <ImageStagingPreviewItem>[
        ImageStagingPreviewItem(
          id: 'invoice-pending',
          kind: ImageStagingPreviewKind.invoice,
          status: ImageStagingPreviewStatus.pending,
          sourceOption: ImageSourceOption.camera,
          title: '發票影像',
          summary: '等待處理',
        ),
        ImageStagingPreviewItem(
          id: 'product-ready',
          kind: ImageStagingPreviewKind.product,
          status: ImageStagingPreviewStatus.ready,
          sourceOption: ImageSourceOption.gallery,
          title: '商品影像',
          summary: '待人工確認',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImageStagingPreviewCard(state: state),
        ),
      ),
    );

    expect(find.text('待審核 1'), findsOneWidget);
    expect(find.text('待審核：1，處理中：1'), findsOneWidget);
    expect(find.text('發票影像'), findsOneWidget);
    expect(find.textContaining('處理中｜等待處理'), findsOneWidget);
    expect(find.text('商品影像'), findsOneWidget);
    expect(find.textContaining('待審核｜待人工確認'), findsOneWidget);
  });
}
