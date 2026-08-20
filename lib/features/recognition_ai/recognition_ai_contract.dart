enum RecognitionAiFallbackReason {
  none,
  quotaExhausted,
  authenticationFailed,
  modelUnavailable,
  serviceUnavailable,
  timeout,
  network,
}

class RecognitionAiRoutingEvent {
  const RecognitionAiRoutingEvent({
    required this.keyGroupAlias,
    required this.model,
    required this.reason,
    required this.physicalRequestSent,
    this.message = '',
  });

  final String keyGroupAlias;
  final String model;
  final RecognitionAiFallbackReason reason;
  final bool physicalRequestSent;
  final String message;

  Map<String, Object?> toSafeJson() => <String, Object?>{
        'key_group_alias': keyGroupAlias,
        'model': model,
        'reason': reason.name,
        'physical_request_sent': physicalRequestSent,
        if (message.isNotEmpty) 'message': message,
      };
}

class RecognitionSessionContext {
  const RecognitionSessionContext({
    required this.logicalInvocationId,
    required this.provider,
    required this.activeModel,
    required this.keyGroupAlias,
    required this.logicalInvocationCount,
    required this.physicalAttemptCount,
    required this.modelAttemptCount,
    required this.keyGroupAttemptCount,
    required this.fallbackReason,
    required this.modelCatalogChecked,
    this.events = const <RecognitionAiRoutingEvent>[],
  });

  final String logicalInvocationId;
  final String provider;
  final String activeModel;
  final String keyGroupAlias;
  final int logicalInvocationCount;
  final int physicalAttemptCount;
  final int modelAttemptCount;
  final int keyGroupAttemptCount;
  final RecognitionAiFallbackReason fallbackReason;
  final bool modelCatalogChecked;
  final List<RecognitionAiRoutingEvent> events;

  RecognitionSessionContext copyWith({
    String? logicalInvocationId,
    String? provider,
    String? activeModel,
    String? keyGroupAlias,
    int? logicalInvocationCount,
    int? physicalAttemptCount,
    int? modelAttemptCount,
    int? keyGroupAttemptCount,
    RecognitionAiFallbackReason? fallbackReason,
    bool? modelCatalogChecked,
    List<RecognitionAiRoutingEvent>? events,
  }) {
    return RecognitionSessionContext(
      logicalInvocationId: logicalInvocationId ?? this.logicalInvocationId,
      provider: provider ?? this.provider,
      activeModel: activeModel ?? this.activeModel,
      keyGroupAlias: keyGroupAlias ?? this.keyGroupAlias,
      logicalInvocationCount:
          logicalInvocationCount ?? this.logicalInvocationCount,
      physicalAttemptCount: physicalAttemptCount ?? this.physicalAttemptCount,
      modelAttemptCount: modelAttemptCount ?? this.modelAttemptCount,
      keyGroupAttemptCount: keyGroupAttemptCount ?? this.keyGroupAttemptCount,
      fallbackReason: fallbackReason ?? this.fallbackReason,
      modelCatalogChecked: modelCatalogChecked ?? this.modelCatalogChecked,
      events: events ?? this.events,
    );
  }

  Map<String, Object?> toSafeJson() => <String, Object?>{
        'provider': provider,
        'logical_invocation_id': logicalInvocationId,
        'active_model': activeModel,
        'key_group_alias': keyGroupAlias,
        'logical_invocation_count': logicalInvocationCount,
        'physical_attempt_count': physicalAttemptCount,
        'model_attempt_count': modelAttemptCount,
        'key_group_attempt_count': keyGroupAttemptCount,
        'fallback_reason': fallbackReason.name,
        'model_catalog_checked': modelCatalogChecked,
        'routing_events': <Object?>[
          for (final event in events) event.toSafeJson(),
        ],
      };
}
