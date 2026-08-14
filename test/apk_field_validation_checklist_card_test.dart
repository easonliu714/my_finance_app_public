import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/apk_field_validation_checklist.dart';
import 'package:my_finance_app/features/invoice/apk_field_validation_checklist_card.dart';

void main() {
  testWidgets('ApkFieldValidationChecklistCard renders release ready summary', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ApkFieldValidationChecklistCard(),
        ),
      ),
    );

    expect(find.byKey(ApkFieldValidationChecklistCard.cardKey), findsOneWidget);
    expect(find.byKey(ApkFieldValidationChecklistCard.summaryKey), findsOneWidget);
    expect(find.text('APK 欄位驗證清單'), findsOneWidget);
    expect(find.text('必要項目已通過，可進入下一步 APK 實機驗證。'), findsOneWidget);
    expect(find.text('通過：4，警告：1，阻擋：0'), findsOneWidget);
    expect(find.text('AI 模型設定可見'), findsOneWidget);
    expect(find.text('影像 staging preview 可見'), findsOneWidget);
    expect(find.text('實機 smoke test'), findsOneWidget);
  });

  testWidgets('ApkFieldValidationChecklistCard renders blocked copy for required fail', (tester) async {
    const checklist = ApkFieldValidationChecklist(
      items: <ApkFieldValidationItem>[
        ApkFieldValidationItem(
          id: 'required-fail',
          title: '必要項目失敗',
          description: '必要項目未通過。',
          status: ApkFieldValidationStatus.fail,
          severity: ApkFieldValidationSeverity.required,
        ),
        ApkFieldValidationItem(
          id: 'optional-na',
          title: '選用項目',
          description: '本階段不適用。',
          status: ApkFieldValidationStatus.notApplicable,
          severity: ApkFieldValidationSeverity.optional,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ApkFieldValidationChecklistCard(checklist: checklist),
        ),
      ),
    );

    expect(find.text('阻擋中'), findsOneWidget);
    expect(find.text('仍有必要項目未通過，暫不可進入 APK release gate。'), findsOneWidget);
    expect(find.text('通過：0，警告：0，阻擋：1'), findsOneWidget);
    expect(find.text('失敗'), findsOneWidget);
    expect(find.text('不適用'), findsOneWidget);
  });
}
