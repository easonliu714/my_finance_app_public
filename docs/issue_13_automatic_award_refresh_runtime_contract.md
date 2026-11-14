# Issue #13 Automatic Award Refresh Runtime Contract

## Current admitted design

The production automatic scheduler is intentionally split into two layers:

1. Android `AlarmManager.setWindow()` is a best-effort wake marker only. The
   native receiver performs no HTTP request, parser work, invoice lookup, or
   accounting write.
2. When the Flutter app process starts or resumes, the app-wide lifecycle
   coordinator consumes the marker, re-checks explicit user consent and the
   timing policy, then invokes the shared headless canonical refresh runner.

The headless runner composes the same production authorities used by the manual
award page:

- `InvoiceAwardProductionRefreshController` for general awards.
- `MinistryOfFinanceCloudAwardForegroundAcquisitionService` for cloud tiers.
- `ExistingInvoiceAwardCandidateRepository` +
  `cloudCandidateNumbersForAwardPeriod` for local-only candidate scoping.

It does not implement another MOF parser, raw HTTP endpoint, or promotion path.

## Concurrency

Manual refresh and app-wide automatic catch-up share
`InvoiceAwardRefreshProcessGate`. Only one official refresh may own the
process at a time. A second request fails closed as busy rather than racing LKG
or candidate-authority promotion.

## Privacy and opt-out

The Android receiver never uploads invoice/accounting data and never performs
network I/O. When automatic refresh consent is disabled, the alarm is cancelled
and pending catch-up markers are cleared. Foreground automatic acquisition is
only admitted after consent and due-policy revalidation.

## Background semantics

This is not represented as unrestricted background network execution. Android
may defer the wake. The admitted contract is best-effort wake + app-wide
foreground catch-up through the canonical production validation/promotion
pipeline.
