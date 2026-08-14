import 'ai_model_entry_rotation.dart';

abstract class AiModelValidationAdapter {
  const AiModelValidationAdapter();

  Future<AiModelValidationResult> validate(AiModelValidationRequest request);
}

class AiModelValidationRequest {
  const AiModelValidationRequest({
    required this.entryId,
    required this.modelId,
    this.requestedAt,
  });

  final String entryId;
  final String modelId;
  final DateTime? requestedAt;
}

class AiModelValidationResult {
  const AiModelValidationResult({
    required this.entryId,
    required this.modelId,
    required this.status,
    required this.message,
    this.checkedAt,
  });

  final String entryId;
  final String modelId;
  final AiModelEntryStatus status;
  final String message;
  final DateTime? checkedAt;

  bool get canBeUsed => status == AiModelEntryStatus.usable;
}

class MockAiModelValidationAdapter extends AiModelValidationAdapter {
  const MockAiModelValidationAdapter({
    this.outcomes = const <String, AiModelEntryStatus>{},
    this.defaultStatus = AiModelEntryStatus.unknown,
    this.now,
  });

  final Map<String, AiModelEntryStatus> outcomes;
  final AiModelEntryStatus defaultStatus;
  final DateTime? now;

  @override
  Future<AiModelValidationResult> validate(AiModelValidationRequest request) async {
    final status = outcomes[request.entryId] ?? defaultStatus;
    return AiModelValidationResult(
      entryId: request.entryId,
      modelId: request.modelId,
      status: status,
      message: _messageFor(status),
      checkedAt: now ?? request.requestedAt,
    );
  }

  static String _messageFor(AiModelEntryStatus status) {
    switch (status) {
      case AiModelEntryStatus.unknown:
        return '尚未確認';
      case AiModelEntryStatus.usable:
        return '可用';
      case AiModelEntryStatus.rejected:
        return '已拒絕';
      case AiModelEntryStatus.quotaExhausted:
        return '額度已用完';
      case AiModelEntryStatus.disabled:
        return '已停用';
    }
  }
}

class AiModelValidationService {
  const AiModelValidationService({required this.adapter});

  final AiModelValidationAdapter adapter;

  Future<AiModelEntryRotationState> validateEntry({
    required AiModelEntryRotationState state,
    required String entryId,
    required String modelId,
    DateTime? requestedAt,
  }) async {
    final result = await adapter.validate(
      AiModelValidationRequest(
        entryId: entryId,
        modelId: modelId,
        requestedAt: requestedAt,
      ),
    );
    return AiModelEntryRotationService.markEntryStatus(
      state: state,
      entryId: result.entryId,
      status: result.status,
      checkedAt: result.checkedAt ?? requestedAt ?? DateTime.now().toUtc(),
    );
  }
}
