import 'authenticated_selector_capability_probe.dart';
import 'official_mobile_selector_capability_profile.dart';

class ContextAwareOfficialMobileSelectorCapabilityReport
    extends OfficialMobileSelectorCapabilityReport {
  const ContextAwareOfficialMobileSelectorCapabilityReport({
    required super.probeSucceeded,
    required super.routeApproved,
    required super.matches,
    required super.availablePageSizes,
    required super.headerMatches,
    required super.issues,
  });

  @override
  bool get canProceedToResultExtraction =>
      probeSucceeded &&
      routeApproved &&
      !isBlocked &&
      officialMobileRequiredResultControls.every(
        (capability) => matches[capability]?.valid ?? false,
      ) &&
      officialMobileRequiredResultHeaders.every(
        (header) => headerMatches[header] ?? false,
      );

  @override
  bool get requiresManualCsvFallback =>
      !canProceedToQueryPopulation && !canProceedToResultExtraction;
}

class ContextAwareOfficialMobileSelectorCapabilityReportParser
    extends OfficialMobileSelectorCapabilityReportParser {
  const ContextAwareOfficialMobileSelectorCapabilityReportParser();

  @override
  AuthenticatedSelectorCapabilityReport parse(Object? rawResult) {
    final base = super.parse(rawResult);
    final hasResultStructure =
        (base.matches[AuthenticatedSelectorCapability.resultTable]?.valid ??
                false) &&
            officialMobileRequiredResultHeaders.every(
              (header) => base.headerMatches[header] ?? false,
            );

    final issues = base.issues.map((issue) {
      final capability = issue.capability;
      final queryControl = capability != null &&
          officialMobileRequiredQueryControls.contains(capability);
      if (!hasResultStructure || !queryControl) return issue;
      if (issue.code != AuthenticatedSelectorProbeIssueCode.missingCapability &&
          issue.code !=
              AuthenticatedSelectorProbeIssueCode.ambiguousCapability) {
        return issue;
      }
      return AuthenticatedSelectorProbeIssue(
        code: issue.code,
        message: issue.message,
        isBlocking: false,
        capability: capability,
        header: issue.header,
      );
    }).toList(growable: false);

    return ContextAwareOfficialMobileSelectorCapabilityReport(
      probeSucceeded: base.probeSucceeded,
      routeApproved: base.routeApproved,
      matches: base.matches,
      availablePageSizes: base.availablePageSizes,
      headerMatches: base.headerMatches,
      issues: issues,
    );
  }
}
