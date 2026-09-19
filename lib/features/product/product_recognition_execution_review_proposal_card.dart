import 'package:flutter/material.dart';

import 'product_multi_item_review_proposal_card.dart';
import 'product_recognition_execution_review_evidence.dart';

/// Presentation-only adapter from coordinator-owned same-request evidence to
/// the compact multi-item proposal card.
///
/// Null/legacy evidence renders nothing. This adapter has no recognition,
/// network, repository, merchant-binding, persistence, or transaction-write
/// authority; it only projects evidence already produced by the coordinator.
class ProductRecognitionExecutionReviewProposalCard extends StatelessWidget {
  const ProductRecognitionExecutionReviewProposalCard({
    super.key,
    required this.evidence,
  });

  final ProductRecognitionExecutionReviewEvidence? evidence;

  @override
  Widget build(BuildContext context) {
    final proposal = evidence?.multiItemProposal;
    if (proposal == null) return const SizedBox.shrink();
    return ProductMultiItemReviewProposalCard(proposal: proposal);
  }
}
