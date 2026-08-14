import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/image_source_permission_status_card.dart';

void main() {
  test('ImageSourcePermissionState exposes camera and gallery status', () {
    const state = ImageSourcePermissionState(
      cameraStatus: ImageSourcePermissionStatus.available,
      galleryStatus: ImageSourcePermissionStatus.denied,
    );

    expect(state.statusFor(DailyCaptureSource.camera), ImageSourcePermissionStatus.available);
    expect(state.statusFor(DailyCaptureSource.gallery), ImageSourcePermissionStatus.denied);
    expect(state.canUse(DailyCaptureSource.camera), isTrue);
    expect(state.canUse(DailyCaptureSource.gallery), isFalse);
    expect(state.needsUserReview(DailyCaptureSource.camera), isFalse);
    expect(state.needsUserReview(DailyCaptureSource.gallery), isTrue);
  });

  testWidgets('ImageSourcePermissionStatusCard renders unknown safe shell', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImageSourcePermissionStatusCard(),
        ),
      ),
    );

    expect(find.byKey(ImageSourcePermissionStatusCard.cardKey), findsOneWidget);
    expect(find.byKey(ImageSourcePermissionStatusCard.cameraStatusKey), findsOneWidget);
    expect(find.byKey(ImageSourcePermissionStatusCard.galleryStatusKey), findsOneWidget);
    expect(find.text('影像來源權限狀態'), findsOneWidget);
    expect(find.text('相機權限'), findsOneWidget);
    expect(find.text('相簿權限'), findsOneWidget);
    expect(find.text('不主動要求'), findsOneWidget);
    expect(find.textContaining('本階段不會主動要求權限'), findsAtLeastNWidgets(1));
    expect(find.textContaining('不會開啟相機或相簿'), findsOneWidget);
  });

  testWidgets('ImageSourcePermissionStatusCard renders denied and restricted guidance', (tester) async {
    const state = ImageSourcePermissionState(
      cameraStatus: ImageSourcePermissionStatus.denied,
      galleryStatus: ImageSourcePermissionStatus.restricted,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImageSourcePermissionStatusCard(state: state),
        ),
      ),
    );

    expect(find.text('已拒絕'), findsOneWidget);
    expect(find.text('受限制'), findsOneWidget);
    expect(find.textContaining('手動開啟'), findsOneWidget);
    expect(find.textContaining('保留手動建立路徑'), findsOneWidget);
  });

  testWidgets('ImageSourcePermissionStatusCard renders permanently denied guidance', (tester) async {
    const state = ImageSourcePermissionState(
      cameraStatus: ImageSourcePermissionStatus.permanentlyDenied,
      galleryStatus: ImageSourcePermissionStatus.available,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImageSourcePermissionStatusCard(state: state),
        ),
      ),
    );

    expect(find.text('永久拒絕'), findsOneWidget);
    expect(find.text('可使用'), findsOneWidget);
    expect(find.textContaining('系統設定'), findsOneWidget);
    expect(find.textContaining('安全接入來源選擇流程'), findsOneWidget);
  });
}
