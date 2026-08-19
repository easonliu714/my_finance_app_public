import 'package:flutter/material.dart';

import 'recognition_ai_contract.dart';

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
        RecognitionAiFallbackReason.quotaExhausted => '配額已滿，已切換 Key Group',
        RecognitionAiFallbackReason.authenticationFailed => '憑證不可用，已切換 Key Group',
        RecognitionAiFallbackReason.modelUnavailable => '模型不可用，已切換 Flash 模型',
        RecognitionAiFallbackReason.serviceUnavailable => 'Gemini 服務暫時不可用，已重試',
        RecognitionAiFallbackReason.timeout => 'Gemini 連線逾時，已重試',
        RecognitionAiFallbackReason.network => 'Gemini 網路失敗，已重試',
      };
}
