import 'package:flutter/material.dart';

import 'recognition_ai_contract.dart';

class RecognitionAiRunningStatusIndicator extends StatelessWidget {
  const RecognitionAiRunningStatusIndicator({
    super.key,
    required this.provider,
    required this.activeModel,
    required this.elapsed,
    this.message = '正在辨識…',
  });

  final String provider;
  final String activeModel;
  final Duration elapsed;
  final String message;

  @override
  Widget build(BuildContext context) {
    final model = activeModel.trim().isEmpty ? '模型確認中' : activeModel.trim();
    return Semantics(
      label: 'AI 辨識進行中',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$provider · $model',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '已等待 ${_formatElapsed(elapsed)} · $message',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RecognitionAiStatusIndicator extends StatelessWidget {
  const RecognitionAiStatusIndicator({
    super.key,
    required this.context,
    this.showKeyGroupAlias = false,
  });

  final RecognitionSessionContext context;
  final bool showKeyGroupAlias;

  @override
  Widget build(BuildContext context) {
    final session = this.context;
    final details = <String>[
      session.provider,
      if (session.activeModel.isNotEmpty) session.activeModel,
      if (showKeyGroupAlias && session.keyGroupAlias.isNotEmpty)
        session.keyGroupAlias,
    ];
    final fallback = _fallbackLabel(session.fallbackReason);
    return Semantics(
      label: 'AI 辨識狀態',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.auto_awesome_outlined, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  details.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (fallback != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    fallback,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _fallbackLabel(RecognitionAiFallbackReason reason) => switch (reason) {
        RecognitionAiFallbackReason.none => null,
        RecognitionAiFallbackReason.quotaExhausted => '配額已滿，已切換下一組 API Key',
        RecognitionAiFallbackReason.authenticationFailed => 'API Key 不可用，已切換下一組',
        RecognitionAiFallbackReason.modelUnavailable => '模型不可用，已切換 Flash 模型',
        RecognitionAiFallbackReason.serviceUnavailable => 'Gemini 服務暫時不可用，已重試',
        RecognitionAiFallbackReason.timeout => 'Gemini 連線逾時，已重試',
        RecognitionAiFallbackReason.network => 'Gemini 網路失敗，已重試',
      };
}

String _formatElapsed(Duration elapsed) {
  final totalSeconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  if (totalSeconds < 60) return '$totalSeconds 秒';
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes 分 ${seconds.toString().padLeft(2, '0')} 秒';
}
