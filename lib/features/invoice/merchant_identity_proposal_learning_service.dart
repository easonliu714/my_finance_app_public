import 'package:sqflite/sqflite.dart';

import '../../database/production_schema_v22.dart';

/// Explicit user outcome for a merchant-identity proposal.
///
/// This is learning evidence only. It never grants sellerTaxId authority,
/// binds a merchant, performs Registry/network work, or writes a transaction.
enum MerchantIdentityProposalOutcome { accept, correct, reject }

class MerchantIdentityProposalLearningService {
  const MerchantIdentityProposalLearningService({required this.database});

  final DatabaseExecutor database;

  Future<void> recordExplicitOutcome({
    required String proposalName,
    required String sellerIdentifier,
    required String sourceReference,
    required MerchantIdentityProposalOutcome outcome,
    required bool explicitUserDecision,
    String? selectedMerchantBrandId,
  }) async {
    if (!explicitUserDecision) {
      throw StateError('MERCHANT_PROPOSAL_EXPLICIT_USER_DECISION_REQUIRED');
    }
    final normalizedProposal = normalizeMerchantIdentityName(proposalName);
    final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalizedProposal.isEmpty) {
      throw ArgumentError.value(proposalName, 'proposalName');
    }
    if (seller.isNotEmpty && seller.length != 8) {
      throw ArgumentError.value(sellerIdentifier, 'sellerIdentifier');
    }
    if (outcome != MerchantIdentityProposalOutcome.reject &&
        (selectedMerchantBrandId?.trim().isEmpty ?? true)) {
      throw StateError('MERCHANT_PROPOSAL_SELECTED_BRAND_REQUIRED');
    }

    await createCanonicalProductionV22Tables(database);
    final now = DateTime.now().toUtc().toIso8601String();
    final decision = outcome == MerchantIdentityProposalOutcome.reject
        ? 'rejected'
        : 'confirmed';
    final source = 'explicit_user_proposal_${outcome.name}';
    final brandId = outcome == MerchantIdentityProposalOutcome.reject
        ? null
        : selectedMerchantBrandId!.trim();
    final id = _stableOutcomeId(
      seller: seller,
      normalizedProposal: normalizedProposal,
      sourceReference: sourceReference,
      outcome: outcome,
      brandId: brandId,
    );

    await database.insert(
      'merchant_identity_observations',
      <String, Object?>{
        'id': id,
        'literal_name': proposalName.trim(),
        'normalized_name': normalizedProposal,
        'seller_identifier': seller,
        'source': source,
        'source_reference': sourceReference.trim(),
        'merchant_brand_id': brandId,
        'legal_entity_id': null,
        'branch_or_outlet_id': null,
        'decision': decision,
        'observed_at': now,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Returns true when an explicit prior rejection exists for the same weak
  /// proposal. Callers may suppress resurfacing it, but this never authorizes
  /// another proposal or silently selects a MerchantBrand.
  Future<bool> wasExplicitlyRejected({
    required String proposalName,
    required String sellerIdentifier,
  }) async {
    await createCanonicalProductionV22Tables(database);
    final normalizedProposal = normalizeMerchantIdentityName(proposalName);
    final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalizedProposal.isEmpty || (seller.isNotEmpty && seller.length != 8)) {
      return false;
    }
    final rows = await database.query(
      'merchant_identity_observations',
      columns: const <String>['id'],
      where: "normalized_name = ? AND seller_identifier = ? AND decision = 'rejected' AND source = 'explicit_user_proposal_reject'",
      whereArgs: <Object?>[normalizedProposal, seller],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  String _stableOutcomeId({
    required String seller,
    required String normalizedProposal,
    required String sourceReference,
    required MerchantIdentityProposalOutcome outcome,
    required String? brandId,
  }) {
    final raw = <String>[
      seller,
      normalizedProposal,
      sourceReference.trim(),
      outcome.name,
      brandId ?? '',
    ].join('|');
    final encoded = raw.codeUnits.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return 'proposal-outcome-$encoded';
  }
}
