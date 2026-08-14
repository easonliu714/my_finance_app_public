import 'package:flutter/material.dart';

import 'image_review_draft.dart';

class ImageReviewDraftCard extends StatelessWidget {
  const ImageReviewDraftCard({super.key, required this.draft});

  static const Key cardKey = Key('image_review_draft_card');
  static const Key invoiceDraftKey = Key('image_review_invoice_draft');
  static const Key transactionDraftKey = Key('image_review_transaction_draft');
  static const Key editActionKey = Key('image_review_draft_edit_action');
  static const Key confirmActionKey = Key('image_review_draft_confirm_action');
  static const Key discardActionKey = Key('image_review_draft_discard_action');

  final ImageReviewDraftCandidate draft;

  bool get canWriteFinalRecordAutomatically => false;

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
                const Icon(Icons.edit_note_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('本機草稿審核', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                _StatusChip(label: _statusLabel(draft.status)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('本機草稿仍需編輯與確認，不會自動寫入正式交易或發票。'),
            const SizedBox(height: 12),
            _DraftTile(draft: draft),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(key: editActionKey, onPressed: null, child: Text('編輯草稿')),
                OutlinedButton(key: confirmActionKey, onPressed: null, child: Text('確認寫入')),
                OutlinedButton(key: discardActionKey, onPressed: null, child: Text('捨棄草稿')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(ImageReviewDraftStatus status) {
    switch (status) {
      case ImageReviewDraftStatus.pendingEdit:
        return '待編輯確認';
      case ImageReviewDraftStatus.discarded:
        return '已捨棄';
    }
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.draft});

  final ImageReviewDraftCandidate draft;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: _draftKey(draft.kind),
      contentPadding: EdgeInsets.zero,
      leading: Icon(draft.kind == ImageReviewDraftKind.invoice ? Icons.receipt_long_outlined : Icons.payments_outlined),
      title: Text(_kindLabel(draft.kind)),
      subtitle: Text('${draft.sourceCandidate.label}｜本機草稿｜需人工確認'),
      trailing: const _StatusChip(label: 'Local'),
    );
  }

  static Key _draftKey(ImageReviewDraftKind kind) {
    switch (kind) {
      case ImageReviewDraftKind.invoice:
        return ImageReviewDraftCard.invoiceDraftKey;
      case ImageReviewDraftKind.transaction:
        return ImageReviewDraftCard.transactionDraftKey;
    }
  }

  static String _kindLabel(ImageReviewDraftKind kind) {
    switch (kind) {
      case ImageReviewDraftKind.invoice:
        return '發票草稿';
      case ImageReviewDraftKind.transaction:
        return '交易草稿';
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
