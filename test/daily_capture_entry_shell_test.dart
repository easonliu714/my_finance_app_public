import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';

void main() {
  test('default daily capture state provides invoice/product and enabled camera/gallery choices', () {
    const state = DailyCaptureEntryState();

    expect(state.entryChoices.length, 2);
    expect(state.entryChoices.map((choice) => choice.intent), contains(DailyCaptureIntent.invoice));
    expect(state.entryChoices.map((choice) => choice.intent), contains(DailyCaptureIntent.product));
    expect(state.sourceChoices.length, 2);
    expect(state.sourceChoices.map((choice) => choice.source), contains(DailyCaptureSource.camera));
    expect(state.sourceChoices.map((choice) => choice.source), contains(DailyCaptureSource.gallery));
    expect(state.sourceChoices.firstWhere((choice) => choice.source == DailyCaptureSource.camera).enabled, isTrue);
    expect(state.sourceChoices.firstWhere((choice) => choice.source == DailyCaptureSource.gallery).enabled, isTrue);
  });

  testWidgets('DailyCaptureEntryCard renders safe daily accounting capture shell', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DailyCaptureEntryCard(),
          ),
        ),
      ),
    );

    expect(find.byKey(DailyCaptureEntryCard.cardKey), findsOneWidget);
    expect(find.byKey(DailyCaptureEntryCard.invoiceChoiceKey), findsOneWidget);
    expect(find.byKey(DailyCaptureEntryCard.productChoiceKey), findsOneWidget);
    expect(find.byKey(DailyCaptureEntryCard.cameraSourceKey), findsOneWidget);
    expect(find.byKey(DailyCaptureEntryCard.gallerySourceKey), findsOneWidget);
    expect(find.text('拍照記帳'), findsOneWidget);
    expect(find.text('掃描發票'), findsOneWidget);
    expect(find.text('拍商品'), findsOneWidget);
    expect(find.text('開啟相機'), findsOneWidget);
    expect(find.text('從相簿選擇'), findsOneWidget);
    expect(find.textContaining('本機待審核'), findsOneWidget);
    expect(find.textContaining('不會上傳影像'), findsOneWidget);
    expect(find.textContaining('不會自動建立交易'), findsOneWidget);

    final cameraButton = tester.widget<OutlinedButton>(find.byKey(DailyCaptureEntryCard.cameraSourceKey));
    final galleryButton = tester.widget<OutlinedButton>(find.byKey(DailyCaptureEntryCard.gallerySourceKey));

    expect(cameraButton.onPressed, isNull);
    expect(galleryButton.onPressed, isNull);
  });

  testWidgets('DailyCaptureEntryCard can wire camera callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyCaptureEntryCard(onCameraSelected: () => tapped = true),
        ),
      ),
    );

    await tester.tap(find.byKey(DailyCaptureEntryCard.cameraSourceKey));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('DailyCaptureEntryCard can wire gallery callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyCaptureEntryCard(onGallerySelected: () => tapped = true),
        ),
      ),
    );

    await tester.tap(find.byKey(DailyCaptureEntryCard.gallerySourceKey));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
