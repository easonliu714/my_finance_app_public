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

  @override
  Future<GeminiInvoiceSettings> load() async => value;

  @override
  Future<void> save(GeminiInvoiceSettings settings) async {
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
            modelCount: 2,
          ),
      ],
      models: const <GeminiModelDescriptor>[
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

  testWidgets('API Key is obscured by default and can be revealed', (
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

  testWidgets('tests explicit groups, loads models and securely saves topology', (
    tester,
  ) async {
    final store = _FakeStore(const GeminiInvoiceSettings());
    await pumpCard(tester, store: store);

    final firstGroup = find.byKey(GeminiInvoiceSettingsCard.apiKeyFieldKey);
    await tester.ensureVisible(firstGroup);
    await tester.enterText(firstGroup, 'KEY_1');

    final addGroup = find.byKey(GeminiInvoiceSettingsCard.addGroupKey);
    await tester.ensureVisible(addGroup);
    await tester.tap(addGroup);
    await tester.pump();

    final secondGroup = find.byKey(GeminiInvoiceSettingsCard.groupFieldKey(1));
    await tester.ensureVisible(secondGroup);
    await tester.enterText(secondGroup, 'KEY_2');
    await tester.pump();

    expect(
      find.text('已解析 2 個 Key Group / 2 組 API Key'),
      findsOneWidget,
    );

    final testButton = find.byKey(GeminiInvoiceSettingsCard.testKey);
    await tester.ensureVisible(testButton);
    await tester.tap(testButton);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('已讀取 2 個'), findsOneWidget);
    expect(find.textContaining('GROUP_A · Key #1'), findsOneWidget);
    expect(find.textContaining('GROUP_B · Key #2'), findsOneWidget);

    final featureSwitch = find.widgetWithText(
      SwitchListTile,
      '啟用 AI 發票覆核',
    );
    await tester.ensureVisible(featureSwitch);
    await tester.tap(featureSwitch);
    await tester.pump();

    final saveButton = find.byKey(GeminiInvoiceSettingsCard.saveKey);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(store.value.apiKeys, <String>['KEY_1', 'KEY_2']);
    expect(store.value.effectiveKeyGroups, hasLength(2));
    expect(store.value.effectiveKeyGroups[0].alias, 'GROUP_A');
    expect(store.value.effectiveKeyGroups[0].apiKeys, <String>['KEY_1']);
    expect(store.value.effectiveKeyGroups[1].alias, 'GROUP_B');
    expect(store.value.effectiveKeyGroups[1].apiKeys, <String>['KEY_2']);
    expect(store.value.model, GeminiInvoiceSettings.defaultModel);
    expect(store.value.experimentalInvoiceVisionEnabled, isTrue);
    expect(store.value.debugToolsEnabled, isTrue);
  });
}
