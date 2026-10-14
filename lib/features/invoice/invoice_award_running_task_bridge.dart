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

  InvoiceAwardRunningTaskSnapshot? snapshotFor(String periodId) =>
      _periodId == periodId ? _snapshot : null;

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
