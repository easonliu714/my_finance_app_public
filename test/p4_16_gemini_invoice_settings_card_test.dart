import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings_card.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_invoice_settings_repository.dart';
import 'package:my_finance_app/features/invoice/gemini/gemini_model_catalog_client.dart';

class _FakeStore extends GeminiInvoiceSettingsRepository {
  _FakeStore(this.value);

  GeminiInvoiceSettings value;
  var clearCount = 0;
  var saveCount = 0;

  @override
  Future<GeminiInvoiceSettings> load() async => value;

  @override
  Future<void> save(GeminiInvoiceSettings settings) async {
    saveCount += 1;
    value = settings;
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
    value = const GeminiInvoiceSettings();
  }
}

class _FakeCatalogClient extends GeminiModelCatalogClient {
  _FakeCatalogClient()
      : super(client: MockClient((_) async => throw UnimplementedError()));

  @override
  Future<GeminiCatalogValidationResult> validateKeysAndLoadModels(
    List<String> apiKeys,
  ) async {
    return GeminiCatalogValidationResult(
      keyResults: <GeminiApiKeyTestResult>[
        for (var index = 0; index < apiKeys.length; index++)
          GeminiApiKeyTestResult(
            ordinal: index + 1,
            maskedKey: GeminiInvoiceSettings.maskApiKey(apiKeys[index]),
            available: true,
            message: '可用',
            modelCount: 3,
          ),
      ],
      models: const <GeminiModelDescriptor>[
        GeminiModelDescriptor(
          id: 'gemini-3.1-flash-lite',
          displayName: 'Gemini 3.1 Flash-Lite',
          supportedGenerationMethods: <String>{'generateContent'},
        ),
        GeminiModelDescriptor(
          id: 'gemini-3.6-flash',
          displayName: 'Gemini 3.6 Flash',
          supportedGenerationMethods: <String>{'generateContent'},
        ),
        GeminiModelDescriptor(
          id: 'gemini-3.5-flash-lite',
          displayName: 'Gemini 3.5 Flash-Lite',
          supportedGenerationMethods: <String>{'generateContent'},
        ),
      ],
    );
  }
}

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required _FakeStore store,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GeminiInvoiceSettingsCard(
              repository: store,
              catalogClient: _FakeCatalogClient(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('API Key pool is obscured by default and can be revealed', (
    tester,
  ) async {
    final store = _FakeStore(
      const GeminiInvoiceSettings(apiKeys: <String>['AIza_TEST_KEY_12345678']),
    );
    await pumpCard(tester, store: store);

    var editable = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(editable.obscureText, isTrue);

    final visibilityToggle =
        find.byKey(GeminiInvoiceSettingsCard.visibilityToggleKey);
    await tester.ensureVisible(visibilityToggle);
    await tester.tap(visibilityToggle);
    await tester.pump();

    editable = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(editable.obscureText, isFalse);
  });

  testWidgets('one pane tests multiple keys and securely saves flat pool', (
    tester,
  ) async {
    final store = _FakeStore(const GeminiInvoiceSettings());
    await pumpCard(tester, store: store);

    final keyField = find.byKey(GeminiInvoiceSettingsCard.apiKeyFieldKey);
    await tester.ensureVisible(keyField);
    await tester.enterText(keyField, 'KEY_1，KEY_2；KEY_3');
    await tester.pump();

    expect(find.text('已解析 3 組 API Key'), findsOneWidget);
    expect(find.byKey(GeminiInvoiceSettingsCard.addGroupKey), findsNothing);

    final testButton = find.byKey(GeminiInvoiceSettingsCard.testKey);
    await tester.ensureVisible(testButton);
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('已讀取 3 個'), findsOneWidget);
    expect(find.textContaining('Key #1'), findsOneWidget);
    expect(find.textContaining('Key #2'), findsOneWidget);
    expect(find.textContaining('Key #3'), findsOneWidget);
    expect(find.textContaining('GROUP_'), findsNothing);

    final featureSwitch = find.widgetWithText(
      SwitchListTile,
      '啟用 AI 發票覆核',
    );
    await tester.ensureVisible(featureSwitch);
    await tester.tap(featureSwitch);
    await tester.pumpAndSettle();

    // Feature switch is now immediate-persist and enables Local-low-confidence
    // auto escalation by default, so the real-device switch state cannot drift
    // from Secure Storage.
    expect(store.value.experimentalInvoiceVisionEnabled, isTrue);
    expect(store.value.autoReviewLowConfidenceEnabled, isTrue);
    expect(store.value.apiKeys, <String>['KEY_1', 'KEY_2', 'KEY_3']);
    expect(store.value.keyGroups, isEmpty);
    expect(store.saveCount, greaterThanOrEqualTo(1));

    final autoSwitch =
        find.byKey(GeminiInvoiceSettingsCard.autoReviewToggleKey);
    await tester.ensureVisible(autoSwitch);
    await tester.tap(autoSwitch);
    await tester.pumpAndSettle();
    expect(store.value.autoReviewLowConfidenceEnabled, isFalse);

    await tester.tap(autoSwitch);
    await tester.pumpAndSettle();
    expect(store.value.autoReviewLowConfidenceEnabled, isTrue);

    final saveButton = find.byKey(GeminiInvoiceSettingsCard.saveKey);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(store.value.apiKeys, <String>['KEY_1', 'KEY_2', 'KEY_3']);
    expect(store.value.model, GeminiInvoiceSettings.defaultModel);
    expect(store.value.experimentalInvoiceVisionEnabled, isTrue);
    expect(store.value.autoReviewLowConfidenceEnabled, isTrue);
    expect(store.value.debugToolsEnabled, isTrue);
  });
}
