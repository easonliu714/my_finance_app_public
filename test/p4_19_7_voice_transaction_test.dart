import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_finance_app/features/transaction/transaction_entry_page.dart';
import 'package:my_finance_app/features/voice/voice_speech_recognition.dart';
import 'package:my_finance_app/features/voice/voice_transaction_entry_page.dart';
import 'package:my_finance_app/features/voice/voice_transaction_parser.dart';

void main() {
  group('P4.19.7 deterministic transcript parser', () {
    const parser = VoiceTransactionParser();

    test('canonical sentence extracts safe accounting candidates', () {
      final candidate = parser.parse(
        VoiceTransactionEntryPage.exampleTranscript,
      );

      expect(candidate.intent, VoiceTransactionIntent.expense);
      expect(candidate.merchantCandidate, 'OK便利商店');
      expect(candidate.accountCandidate, '一卡通');
      expect(candidate.amount, 72);
      expect(candidate.items, hasLength(2));
      expect(candidate.items[0].name, '大熱拿');
      expect(candidate.items[0].quantity, 1);
      expect(candidate.items[1].name, '花生吐司');
      expect(candidate.items[1].quantity, 1);
      expect(candidate.warnings, isEmpty);
    });

    test('unknown or ambiguous accounting evidence fails closed', () {
      final candidate = parser.parse('昨天可能有買東西，金額不確定');

      expect(candidate.intent, VoiceTransactionIntent.unknown);
      expect(candidate.amount, isNull);
      expect(candidate.accountCandidate, isEmpty);
      expect(candidate.warnings, isNotEmpty);
    });

    test('formal reference matcher requires one deterministic match', () {
      expect(
        VoiceTransactionReferenceMatcher.matchUnique(
          '一卡通',
          const ['現金', '一卡通 Money'],
        ),
        '一卡通 Money',
      );
      expect(
        VoiceTransactionReferenceMatcher.matchUnique(
          '台新',
          const ['台新信用卡', '台新銀行'],
        ),
        isNull,
      );
      expect(
        VoiceTransactionReferenceMatcher.matchUnique(
          '不存在帳戶',
          const ['現金', '一卡通'],
        ),
        isNull,
      );
    });
  });

  testWidgets('permission unavailable keeps editable text fallback', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceTransactionEntryPage(
          speechPort: _UnavailableSpeechPort(),
          categoryOptionsOverride: const ['早餐'],
          merchantOptionsOverride: const ['OK便利商店'],
          accountOptionsOverride: const ['一卡通'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(VoiceTransactionEntryPage.microphoneKey));
    await tester.pumpAndSettle();

    expect(find.byKey(VoiceTransactionEntryPage.transcriptFieldKey), findsOneWidget);
    expect(find.textContaining('仍可直接輸入文字'), findsOneWidget);
  });

  testWidgets('review confirmation stays draft-only and handoff uses reviewed seed',
      (tester) async {
    _useTallViewport(tester);
    TransactionEntrySeed? capturedSeed;
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/voice-test',
      routes: [
        GoRoute(
          path: '/voice-test',
          builder: (context, state) => VoiceTransactionEntryPage(
            speechPort: _UnavailableSpeechPort(),
            categoryOptionsOverride: const ['早餐'],
            merchantOptionsOverride: const ['OK便利商店'],
            accountOptionsOverride: const ['一卡通 Money'],
          ),
        ),
        GoRoute(
          path: '/transaction-test',
          name: TransactionEntryPage.routeName,
          builder: (context, state) {
            capturedSeed = state.extra as TransactionEntrySeed?;
            return const Scaffold(body: Text('transaction-seed-received'));
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(VoiceTransactionEntryPage.exampleKey));
    await tester.tap(find.byKey(VoiceTransactionEntryPage.parseKey));
    await tester.pumpAndSettle();

    expect(find.text('交易類型：支出'), findsOneWidget);
    expect(find.text('商家候選：OK便利商店'), findsOneWidget);
    expect(find.text('付款候選：一卡通'), findsOneWidget);
    expect(find.text('總金額：72'), findsOneWidget);

    await tester.tap(find.byKey(VoiceTransactionEntryPage.categoryKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('早餐').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(VoiceTransactionEntryPage.confirmKey));
    await tester.pumpAndSettle();

    expect(find.text('目前仍是交易草稿；尚未建立任何正式交易。'), findsOneWidget);
    expect(find.byKey(VoiceTransactionEntryPage.handoffKey), findsOneWidget);

    await tester.tap(find.byKey(VoiceTransactionEntryPage.handoffKey));
    await tester.pumpAndSettle();

    expect(find.text('transaction-seed-received'), findsOneWidget);
    expect(capturedSeed, isNotNull);
    expect(capturedSeed!.amount, 72);
    expect(capturedSeed!.accountName, '一卡通 Money');
    expect(capturedSeed!.merchantName, 'OK便利商店');
    expect(capturedSeed!.category, '早餐');
    expect(capturedSeed!.note, contains('來源：語音／文字快速記帳'));
    expect(capturedSeed!.note, contains('大熱拿 × 1'));
    expect(capturedSeed!.note, contains('花生吐司 × 1'));
    expect(capturedSeed!.note, isNot(contains(VoiceTransactionEntryPage.exampleTranscript)));
  });

  testWidgets('post-confirm edit invalidates stale handoff authority', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceTransactionEntryPage(
          speechPort: _UnavailableSpeechPort(),
          categoryOptionsOverride: const ['早餐'],
          merchantOptionsOverride: const ['OK便利商店'],
          accountOptionsOverride: const ['一卡通'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(VoiceTransactionEntryPage.exampleKey));
    await tester.tap(find.byKey(VoiceTransactionEntryPage.parseKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(VoiceTransactionEntryPage.categoryKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('早餐').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(VoiceTransactionEntryPage.confirmKey));
    await tester.pumpAndSettle();
    expect(find.byKey(VoiceTransactionEntryPage.handoffKey), findsOneWidget);

    await tester.enterText(
      find.byKey(VoiceTransactionEntryPage.amountKey),
      '70',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(VoiceTransactionEntryPage.reconfirmKey), findsOneWidget);
    expect(find.byKey(VoiceTransactionEntryPage.handoffKey), findsNothing);
  });
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _UnavailableSpeechPort implements VoiceSpeechRecognitionPort {
  @override
  bool get isListening => false;

  @override
  Future<void> cancel() async {}

  @override
  Future<VoiceSpeechStartResult> start({
    required VoiceSpeechResultCallback onResult,
    required VoiceSpeechStatusCallback onStatus,
    required VoiceSpeechErrorCallback onError,
  }) async {
    return const VoiceSpeechStartResult(
      started: false,
      message: '語音辨識不可用或麥克風權限未授權；你仍可直接輸入文字。',
    );
  }

  @override
  Future<void> stop() async {}
}
