import 'package:flutter/material.dart';

import 'image_review_adapter.dart';

class ImageCandidateReviewCard extends StatelessWidget {
  const ImageCandidateReviewCard({super.key, required this.result});

  static const Key cardKey = Key('image_candidate_review_card');
  static const Key blockedStateKey = Key('image_candidate_review_blocked_state');
  static const Key failedStateKey = Key('image_candidate_review_failed_state');
  static const Key readyStateKey = Key('image_candidate_review_ready_state');
  static const Key acceptActionKey = Key('image_candidate_review_accept_action');
  static const Key editActionKey = Key('image_candidate_review_edit_action');
  static const Key discardActionKey = Key('image_candidate_review_discard_action');

  final ImageReviewAdapterResult result;

  bool get canCreateTransactionAutomatically => false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('辨識候選審核', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                _StatusChip(label: _statusLabel(result.status)),
              ],
            ),
            const SizedBox(height: 8),
            Text(result.message),
            const SizedBox(height: 8),
            const Text('辨識結果只作為待審核候選，不會自動建立交易或發票。'),
            const SizedBox(height: 12),
            _stateBody(),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(key: acceptActionKey, onPressed: null, child: Text('確認採用')),
                OutlinedButton(key: editActionKey, onPressed: null, child: Text('編輯候選')),
                OutlinedButton(key: discardActionKey, onPressed: null, child: Text('捨棄')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stateBody() {
    switch (result.status) {
      case ImageReviewAdapterStatus.blockedByConsent:
        return const ListTile(
          key: blockedStateKey,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.lock_outline),
          title: Text('等待同意'),
          subtitle: Text('需先取得同意，不能靜默建立候選。'),
        );
      case ImageReviewAdapterStatus.failed:
        return const ListTile(
          key: failedStateKey,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.error_outline),
          title: Text('辨識失敗'),
          subtitle: Text('請保留手動輸入或重新建立待審核項目。'),
        );
      case ImageReviewAdapterStatus.readyForReview:
        return Column(
          key: readyStateKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final candidate in result.candidates) _CandidateTile(candidate: candidate)],
        );
    }
  }

  static String _statusLabel(ImageReviewAdapterStatus status) {
    switch (status) {
      case ImageReviewAdapterStatus.readyForReview:
        return '待審核';
      case ImageReviewAdapterStatus.blockedByConsent:
        return '需同意';
      case ImageReviewAdapterStatus.failed:
        return '失敗';
    }
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate});

  final ImageReviewCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final amount = candidate.referenceAmount;
    final subtitleParts = <String>[
      _kindLabel(candidate.kind),
      if (amount != null) '參考金額 ${amount.toStringAsFixed(0)}',
      if (candidate.note != null && candidate.note!.isNotEmpty) candidate.note!,
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(candidate.kind == ImageReviewCandidateKind.invoice ? Icons.receipt_long_outlined : Icons.shopping_bag_outlined),
      title: Text(candidate.label),
      subtitle: Text(subtitleParts.join('｜')),
      trailing: const _StatusChip(label: '候選'),
    );
  }

  static String _kindLabel(ImageReviewCandidateKind kind) {
    switch (kind) {
      case ImageReviewCandidateKind.invoice:
        return '發票';
      case ImageReviewCandidateKind.product:
        return '商品';
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Chip(
      label: Text(label),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
    );
  }
}
