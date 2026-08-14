import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_generation_guard.dart';
import 'package:my_finance_app/features/plan/credit_card_installment_repository.dart';

void main() {
  group('markScheduleItemGeneratedPreview', () {
    test('marks pending schedule item as billed with generated transaction id', () {
      final result = markScheduleItemGeneratedPreview(
        GeneratedInstallmentTransactionGuardInput(scheduleItem: _item(), generatedTransactionId: 'tx-1'),
      );

      expect(result.isPersistencePreview, isTrue);
      expect(result.previousStatus, InstallmentScheduleItemStatus.pending);
      expect(result.nextStatus, InstallmentScheduleItemStatus.billed);
      expect(result.generatedTransactionId, 'tx-1');
      expect(result.updatedScheduleItem.generatedTransactionId, 'tx-1');
      expect(result.updatedScheduleItem.status, InstallmentScheduleItemStatus.billed);
    });

    test('keeps billed schedule item billed when generated transaction id is attached', () {
      final result = markScheduleItemGeneratedPreview(
        GeneratedInstallmentTransactionGuardInput(
          scheduleItem: _item(status: InstallmentScheduleItemStatus.billed),
          generatedTransactionId: 'tx-2',
        ),
      );

      expect(result.previousStatus, InstallmentScheduleItemStatus.billed);
      expect(result.nextStatus, InstallmentScheduleItemStatus.billed);
      expect(result.updatedScheduleItem.generatedTransactionId, 'tx-2');
      expect(result.updatedScheduleItem.status, InstallmentScheduleItemStatus.billed);
    });

    test('trims generated transaction id', () {
      final result = markScheduleItemGeneratedPreview(
        GeneratedInstallmentTransactionGuardInput(scheduleItem: _item(), generatedTransactionId: '  tx-trim  '),
      );

      expect(result.generatedTransactionId, 'tx-trim');
      expect(result.updatedScheduleItem.generatedTransactionId, 'tx-trim');
    });

    test('rejects blank generated transaction id', () {
      expect(
        () => markScheduleItemGeneratedPreview(
          GeneratedInstallmentTransactionGuardInput(scheduleItem: _item(), generatedTransactionId: '   '),
        ),
        throwsA(isA<GeneratedInstallmentTransactionBlocked>()),
      );
    });

    test('rejects schedule item that already has generated transaction id', () {
      expect(
        () => markScheduleItemGeneratedPreview(
          GeneratedInstallmentTransactionGuardInput(scheduleItem: _item(generatedTransactionId: 'existing-tx'), generatedTransactionId: 'tx-1'),
        ),
        throwsA(isA<GeneratedInstallmentTransactionBlocked>()),
      );
    });

    test('rejects paid and cancelled schedule items', () {
      for (final status in [InstallmentScheduleItemStatus.paid, InstallmentScheduleItemStatus.cancelled]) {
        expect(
          () => markScheduleItemGeneratedPreview(
            GeneratedInstallmentTransactionGuardInput(scheduleItem: _item(status: status), generatedTransactionId: 'tx-1'),
          ),
          throwsA(isA<GeneratedInstallmentTransactionBlocked>()),
        );
      }
    });

    test('rejects zero or negative total payment', () {
      for (final totalPayment in [0.0, -1.0]) {
        expect(
          () => markScheduleItemGeneratedPreview(
            GeneratedInstallmentTransactionGuardInput(scheduleItem: _item(totalPayment: totalPayment), generatedTransactionId: 'tx-1'),
          ),
          throwsA(isA<GeneratedInstallmentTransactionBlocked>()),
        );
      }
    });
  });

  group('canHardCancelScheduleItem', () {
    test('allows pending and billed items without generated transaction id', () {
      expect(canHardCancelScheduleItem(_item()), isTrue);
      expect(canHardCancelScheduleItem(_item(status: InstallmentScheduleItemStatus.billed)), isTrue);
    });

    test('blocks paid cancelled or generated items', () {
      expect(canHardCancelScheduleItem(_item(status: InstallmentScheduleItemStatus.paid)), isFalse);
      expect(canHardCancelScheduleItem(_item(status: InstallmentScheduleItemStatus.cancelled)), isFalse);
      expect(canHardCancelScheduleItem(_item(generatedTransactionId: 'tx-1')), isFalse);
    });
  });
}

InstallmentScheduleItemRecord _item({
  InstallmentScheduleItemStatus status = InstallmentScheduleItemStatus.pending,
  String? generatedTransactionId,
  double totalPayment = 2030,
}) {
  return InstallmentScheduleItemRecord(
    id: 'item-1',
    planId: 'plan-1',
    periodNumber: 1,
    statementDate: DateTime(2026, 8, 5),
    principal: 2000,
    fee: 30,
    totalPayment: totalPayment,
    remainingPrincipalAfterPayment: 10000,
    revolvingExposureOffset: 0,
    revolvingExposureAfterOffset: 0,
    generatedTransactionId: generatedTransactionId,
    status: status,
  );
}
