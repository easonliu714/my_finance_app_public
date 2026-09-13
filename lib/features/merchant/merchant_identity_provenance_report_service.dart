import 'package:sqflite/sqflite.dart';

import 'merchant_branch_outlet_history_service.dart';
import 'merchant_identity_repository.dart';
import 'merchant_legal_name_history_service.dart';

/// Read-only P4.20.5 report projection that keeps bookkeeping brand identity,
/// official legal-name observations, branch/outlet lineage, and effective
/// binding periods separate while making their provenance inspectable.
///
/// This service never grants sellerTaxId authority, never learns from a weak
/// OCR/AI or Registry hit, never binds a merchant, and never writes accounting
/// data. Historical transaction references remain outside this projection.
class MerchantIdentityProvenanceReport {
  const MerchantIdentityProvenanceReport({
    required this.sellerIdentifier,
    required this.currentIdentity,
    required this.bindingHistory,
    required this.legalNameHistory,
    required this.branchOutletHistory,
  });

  final String sellerIdentifier;
  final ConfirmedMerchantIdentity? currentIdentity;
  final List<MerchantIdentityBindingPeriod> bindingHistory;
  final List<MerchantLegalNameObservation> legalNameHistory;
  final List<MerchantBranchOutletHistoryEntry> branchOutletHistory;

  bool get hasCurrentBinding => currentIdentity != null;
}

class MerchantIdentityProvenanceReportService {
  const MerchantIdentityProvenanceReportService({this.database});

  final DatabaseExecutor? database;

  Future<MerchantIdentityProvenanceReport> buildForSellerIdentifier(
    String sellerIdentifier,
  ) async {
    final seller = sellerIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^\d{8}$').hasMatch(seller)) {
      return MerchantIdentityProvenanceReport(
        sellerIdentifier: seller,
        currentIdentity: null,
        bindingHistory: const <MerchantIdentityBindingPeriod>[],
        legalNameHistory: const <MerchantLegalNameObservation>[],
        branchOutletHistory: const <MerchantBranchOutletHistoryEntry>[],
      );
    }

    final repository = MerchantIdentityRepository(database: database);
    final legalNames = MerchantLegalNameHistoryService(database: database);
    final branches = MerchantBranchOutletHistoryService(database: database);

    // Keep each domain projection independent. A missing current MerchantBrand
    // must not hide historical legal-name or branch/outlet provenance.
    final current = await repository.findConfirmedBySellerIdentifier(seller);
    final bindings =
        await repository.listBindingHistoryForSellerIdentifier(seller);
    final legalHistory = await legalNames.listForSellerIdentifier(seller);
    final branchHistory = await branches.listForSellerIdentifier(seller);

    return MerchantIdentityProvenanceReport(
      sellerIdentifier: seller,
      currentIdentity: current,
      bindingHistory: List<MerchantIdentityBindingPeriod>.unmodifiable(bindings),
      legalNameHistory:
          List<MerchantLegalNameObservation>.unmodifiable(legalHistory),
      branchOutletHistory:
          List<MerchantBranchOutletHistoryEntry>.unmodifiable(branchHistory),
    );
  }
}
