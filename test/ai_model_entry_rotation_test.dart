import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/ai_model_entry_rotation.dart';

void main() {
  test('selects first usable entry when no preferred entry exists', () {
    const entries = <AiModelEntry>[
      AiModelEntry(id: 'a', maskedLabel: '••••0001', status: AiModelEntryStatus.rejected),
      AiModelEntry(id: 'b', maskedLabel: '••••0002', status: AiModelEntryStatus.usable),
      AiModelEntry(id: 'c', maskedLabel: '••••0003', status: AiModelEntryStatus.unknown),
    ];

    final selected = AiModelEntryRotationService.selectUsableEntry(entries);

    expect(selected?.id, 'b');
  });

  test('prefers last successful entry when it is still usable', () {
    const state = AiModelEntryRotationState(
      entries: <AiModelEntry>[
        AiModelEntry(id: 'a', maskedLabel: '••••0001', status: AiModelEntryStatus.usable),
        AiModelEntry(id: 'b', maskedLabel: '••••0002', status: AiModelEntryStatus.usable),
      ],
      lastSuccessfulEntryId: 'b',
    );

    expect(state.activeEntry?.id, 'b');
  });

  test('skips preferred entry when it is unavailable', () {
    const state = AiModelEntryRotationState(
      entries: <AiModelEntry>[
        AiModelEntry(id: 'a', maskedLabel: '••••0001', status: AiModelEntryStatus.quotaExhausted),
        AiModelEntry(id: 'b', maskedLabel: '••••0002', status: AiModelEntryStatus.usable),
      ],
      lastSuccessfulEntryId: 'a',
    );

    expect(state.activeEntry?.id, 'b');
  });

  test('returns null when no entry is usable', () {
    const entries = <AiModelEntry>[
      AiModelEntry(id: 'a', maskedLabel: '••••0001', status: AiModelEntryStatus.rejected),
      AiModelEntry(id: 'b', maskedLabel: '••••0002', status: AiModelEntryStatus.disabled),
      AiModelEntry(id: 'c', maskedLabel: '••••0003', status: AiModelEntryStatus.quotaExhausted),
    ];

    final selected = AiModelEntryRotationService.selectUsableEntry(entries);

    expect(selected, isNull);
  });

  test('markEntryStatus records usable entry as last successful', () {
    final checkedAt = DateTime.utc(2026, 6, 11, 0, 0);
    const state = AiModelEntryRotationState(
      entries: <AiModelEntry>[
        AiModelEntry(id: 'a', maskedLabel: '••••0001'),
        AiModelEntry(id: 'b', maskedLabel: '••••0002'),
      ],
    );

    final updated = AiModelEntryRotationService.markEntryStatus(
      state: state,
      entryId: 'b',
      status: AiModelEntryStatus.usable,
      checkedAt: checkedAt,
    );

    expect(updated.lastSuccessfulEntryId, 'b');
    expect(updated.entries.last.status, AiModelEntryStatus.usable);
    expect(updated.entries.last.lastCheckedAt, checkedAt);
  });
}
