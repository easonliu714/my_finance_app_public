import 'package:flutter/foundation.dart';

import 'existing_invoice_award_candidate_repository.dart';
import 'existing_invoice_award_cloud_batch_matcher.dart';
import 'existing_invoice_award_general_batch_matcher.dart';
import 'invoice_award_cloud_eligibility_confirmation.dart';
import 'invoice_award_official_dataset.dart';

/// Read-only snapshot of the currently authorized *process-local* refresh.
/// This is UI observation only, never official/native completion evidence.
@immutable
class InvoiceAwardRunningTaskSnapshot {
  const InvoiceAwardRunningTaskSnapshot({
    required this.periodId,
    required this.status,
    required this.cloudStatus,
    required this.scanStatus,
    this.cloudDiagnosticStatus = '',
    this.tierSummaries = const <String, String>{},
    this.activeTierCode,
    this.cloudComplete = false,
    this.generalDataset,
    this.candidates = const <ExistingInvoiceAwardCandidate>[],
    this.generalEvaluations = const <ExistingInvoiceAwardGeneralEvaluation>[],
    this.cloudEvaluations = const <ExistingInvoiceAwardCloudEvaluation>[],
    this.confirmations = const <String, InvoiceAwardCloudEligibilityConfirmation>{},
  });

  final String periodId;
  final String status;
  final String cloudStatus;
  final String scanStatus;
  final String cloudDiagnosticStatus;
  final Map<String, String> tierSummaries;
  final String? activeTierCode;
  final bool cloudComplete;
  final OfficialInvoiceAwardDataset? generalDataset;
  final List<ExistingInvoiceAwardCandidate> candidates;
  final List<ExistingInvoiceAwardGeneralEvaluation> generalEvaluations;
  final List<ExistingInvoiceAwardCloudEvaluation> cloudEvaluations;
  final Map<String, InvoiceAwardCloudEligibilityConfirmation> confirmations;

  /// Route reentry must not resurrect pre-deferral cloud-500 WIN/NOT_WIN.
  /// This is a read-only copy: the original snapshot and audit records remain
  /// untouched, while general and independently verified other-tier evidence
  /// remains available. Production calls this only with compile-time release.
  InvoiceAwardRunningTaskSnapshot withoutDeferredCloud500Authority() {
    final safeEvaluations = cloudEvaluations.map((value) {
      final deferredMatch = value.selectedTierCode == 'cloud-500';
      final selectedTier = deferredMatch ? null : value.selectedTierCode;
      final incomplete = deferredMatch ||
          value.status == ExistingInvoiceAwardCloudEvaluationStatus.notMatched;
      return ExistingInvoiceAwardCloudEvaluation(
        candidate: value.candidate,
        status: incomplete
            ? ExistingInvoiceAwardCloudEvaluationStatus.authorityIncomplete
            : value.status,
        missingTierCodes: Set<String>.unmodifiable(
          <String>{...value.missingTierCodes, 'cloud-500'},
        ),
        matchedTierCodes: Set<String>.unmodifiable(
          <String>{...value.matchedTierCodes}..remove('cloud-500'),
        ),
        selectedTierCode: selectedTier,
        grossAmount: selectedTier == null ? 0 : value.grossAmount,
        indexSha256: selectedTier == null ? null : value.indexSha256,
        pdfSha256: selectedTier == null ? null : value.pdfSha256,
      );
    }).toList(growable: false);
    return InvoiceAwardRunningTaskSnapshot(
      periodId: periodId,
      status: status,
      cloudStatus: '雲端 500 元獎正式功能暫緩；其他獎別仍需各自驗證。',
      scanStatus: '雲端 500 元獎無完整判定；一般獎依已驗證官方資料顯示。',
      tierSummaries: Map<String, String>.unmodifiable(
        <String, String>{...tierSummaries}..remove('cloud-500'),
      ),
      activeTierCode: activeTierCode == 'cloud-500' ? null : activeTierCode,
      cloudComplete: false,
      generalDataset: generalDataset,
      candidates: candidates,
      generalEvaluations: generalEvaluations,
      cloudEvaluations: List<ExistingInvoiceAwardCloudEvaluation>.unmodifiable(
        safeEvaluations,
      ),
      confirmations: Map<String, InvoiceAwardCloudEligibilityConfirmation>.unmodifiable(
        <String, InvoiceAwardCloudEligibilityConfirmation>{...confirmations}
          ..removeWhere((_, value) => value.tierCode == 'cloud-500'),
      ),
    );
  }
}

/// One in-process publisher; any number of UI routes may safely subscribe.
/// The generation lease rejects stale updates. The ledger is deliberately
/// not persisted across Android process death: UNKNOWN is not RUNNING.
class InvoiceAwardRunningTaskBridge extends ChangeNotifier {
  InvoiceAwardRunningTaskBridge();

  static final InvoiceAwardRunningTaskBridge shared =
      InvoiceAwardRunningTaskBridge();

  String? _periodId;
  bool _active = false;
  int _generation = 0;
  InvoiceAwardRunningTaskSnapshot? _snapshot;

  String? get periodId => _periodId;
  bool get active => _active;
  int get generation => _generation;

  bool activeFor(String periodId) => _active && _periodId == periodId;

  // A stale in-process snapshot is never a release cloud-500 authority.
  // Debug diagnostics retain their historical replay behavior.
  InvoiceAwardRunningTaskSnapshot? snapshotFor(String periodId) {
    if (_periodId != periodId) return null;
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    return kReleaseMode
        ? snapshot.withoutDeferredCloud500Authority()
        : snapshot;
  }

  bool begin(String periodId) {
    if (_active) return false;
    _generation++;
    _periodId = periodId;
    _snapshot = null;
    _active = true;
    notifyListeners();
    return true;
  }

  void publish(int generation, InvoiceAwardRunningTaskSnapshot snapshot) {
    if (!_active ||
        generation != _generation ||
        snapshot.periodId != _periodId) {
      return;
    }
    _snapshot = snapshot;
    notifyListeners();
  }

  void finish(int generation, String periodId) {
    if (!_active || generation != _generation || periodId != _periodId) {
      return;
    }
    _active = false;
    notifyListeners();
  }
}
