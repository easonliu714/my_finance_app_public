import 'draft_persistence_dry_run.dart';

class DraftStorageWriteRequest {
  const DraftStorageWriteRequest({
    required this.dryRunResult,
    required this.approved,
  });

  final DraftPersistenceDryRunResult dryRunResult;
  final bool approved;
}

class DraftStorageWriteResult {
  const DraftStorageWriteResult({
    required this.accepted,
    required this.payload,
    required this.message,
  });

  final bool accepted;
  final Map<String, Object?>? payload;
  final String message;

  bool get isLocalOnly => true;
  bool get requiresManualReview => true;
  bool get canWriteFinalRecordAutomatically => false;
}

abstract class DraftStorageAdapter {
  Future<void> writeDraftPayload(Map<String, Object?> payload);
  Future<List<Map<String, Object?>>> listDraftPayloads();
}

class InMemoryDraftStorageAdapter implements DraftStorageAdapter {
  final List<Map<String, Object?>> _payloads = <Map<String, Object?>>[];

  @override
  Future<void> writeDraftPayload(Map<String, Object?> payload) async {
    _payloads.add(Map<String, Object?>.unmodifiable(payload));
  }

  @override
  Future<List<Map<String, Object?>>> listDraftPayloads() async {
    return List<Map<String, Object?>>.unmodifiable(_payloads);
  }
}

class DraftStorageWriteService {
  const DraftStorageWriteService({required this.adapter});

  final DraftStorageAdapter adapter;

  Future<DraftStorageWriteResult> guardedWrite(DraftStorageWriteRequest request) async {
    if (!request.approved) {
      return const DraftStorageWriteResult(
        accepted: false,
        payload: null,
        message: '需先核准本機草稿寫入，才可進入 guarded write。',
      );
    }
    if (!request.dryRunResult.accepted) {
      return const DraftStorageWriteResult(
        accepted: false,
        payload: null,
        message: 'dry-run payload 未通過，不能進入 guarded write。',
      );
    }
    await adapter.writeDraftPayload(request.dryRunResult.payload);
    return DraftStorageWriteResult(
      accepted: true,
      payload: request.dryRunResult.payload,
      message: '已完成 guarded write prototype。',
    );
  }
}

class DraftStorageAdapterCopy {
  const DraftStorageAdapterCopy._();

  static const String prototypeOnly = '此階段只建立 guarded write prototype，不接正式資料庫。';
  static const String reviewBoundary = 'guarded write 仍只保存本機待審核草稿，不會自動建立正式紀錄。';
}
