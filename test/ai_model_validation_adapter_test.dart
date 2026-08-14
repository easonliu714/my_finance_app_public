import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/ai_model_entry_rotation.dart';
import 'package:my_finance_app/features/invoice/ai_model_validation_adapter.dart';

void main() {
  test('mock validation returns usable result for configured entry', () async {
    final checkedAt = DateTime.utc(2026, 6, 11, 1, 30);
    const adapter = MockAiModelValidationAdapter(
      outcomes: <String, AiModelEntryStatus>{'entry-a': AiModelEntryStatus.usable},
    );

    final result = await adapter.validate(
      AiModelValidationRequest(
        entryId: 'entry-a',
        modelId: 'gemini-flash-latest',
        requestedAt: checkedAt,
      ),
    );

    expect(result.entryId, 'entry-a');
    expect(result.modelId, 'gemini-flash-latest');
    expect(result.status, AiModelEntryStatus.usable);
    expect(result.canBeUsed, isTrue);
    expect(result.message, '可用');
    expect(result.checkedAt, checkedAt);
  });

  test('mock validation maps configured failure classes', () async {
    const adapter = MockAiModelValidationAdapter(
      outcomes: <String, AiModelEntryStatus>{
        'rejected': AiModelEntryStatus.rejected,
        'quota': AiModelEntryStatus.quotaExhausted,
        'disabled': AiModelEntryStatus.disabled,
      },
    );

    final rejected = await adapter.validate(const AiModelValidationRequest(entryId: 'rejected', modelId: 'm'));
    final quota = await adapter.validate(const AiModelValidationRequest(entryId: 'quota', modelId: 'm'));
    final disabled = await adapter.validate(const AiModelValidationRequest(entryId: 'disabled', modelId: 'm'));

    expect(rejected.status, AiModelEntryStatus.rejected);
    expect(rejected.message, '已拒絕');
    expect(quota.status, AiModelEntryStatus.quotaExhausted);
    expect(quota.message, '額度已用完');
    expect(disabled.status, AiModelEntryStatus.disabled);
    expect(disabled.message, '已停用');
  });

  test('mock validation uses default unknown status when no outcome is configured', () async {
    const adapter = MockAiModelValidationAdapter();

    final result = await adapter.validate(const AiModelValidationRequest(entryId: 'missing', modelId: 'm'));

    expect(result.status, AiModelEntryStatus.unknown);
    expect(result.message, '尚未確認');
    expect(result.canBeUsed, isFalse);
  });

  test('validation service updates entry status and last successful entry', () async {
    final checkedAt = DateTime.utc(2026, 6, 11, 1, 35);
    const state = AiModelEntryRotationState(
      entries: <AiModelEntry>[
        AiModelEntry(id: 'entry-a', maskedLabel: '••••0001'),
        AiModelEntry(id: 'entry-b', maskedLabel: '••••0002'),
      ],
    );
    final service = AiModelValidationService(
      adapter: MockAiModelValidationAdapter(
        outcomes: const <String, AiModelEntryStatus>{'entry-b': AiModelEntryStatus.usable},
        now: checkedAt,
      ),
    );

    final updated = await service.validateEntry(
      state: state,
      entryId: 'entry-b',
      modelId: 'gemini-flash-latest',
      requestedAt: checkedAt,
    );

    expect(updated.lastSuccessfulEntryId, 'entry-b');
    expect(updated.entries.last.status, AiModelEntryStatus.usable);
    expect(updated.entries.last.lastCheckedAt, checkedAt);
  });

  test('validation service keeps last successful entry when validation is not usable', () async {
    final checkedAt = DateTime.utc(2026, 6, 11, 1, 40);
    const state = AiModelEntryRotationState(
      entries: <AiModelEntry>[
        AiModelEntry(id: 'entry-a', maskedLabel: '••••0001', status: AiModelEntryStatus.usable),
        AiModelEntry(id: 'entry-b', maskedLabel: '••••0002'),
      ],
      lastSuccessfulEntryId: 'entry-a',
    );
    final service = AiModelValidationService(
      adapter: MockAiModelValidationAdapter(
        outcomes: const <String, AiModelEntryStatus>{'entry-b': AiModelEntryStatus.quotaExhausted},
        now: checkedAt,
      ),
    );

    final updated = await service.validateEntry(
      state: state,
      entryId: 'entry-b',
      modelId: 'gemini-flash-latest',
      requestedAt: checkedAt,
    );

    expect(updated.lastSuccessfulEntryId, 'entry-a');
    expect(updated.entries.last.status, AiModelEntryStatus.quotaExhausted);
    expect(updated.activeEntry?.id, 'entry-a');
  });
}
