# Issue #13 Winning Notification Runtime Contract

## Scope

This slice implements local, user-controlled winner notifications. It does not
claim prizes, configure Ministry of Finance remittance, or create accounting
transactions.

## Authority gate

A winner notification is eligible only after both current official award
domains are validated and local matching has completed. General winners are
eligible. Cloud-exclusive results are eligible only when the cloud matcher
reports a confirmed eligible match; review-required number matches are not
announced as confirmed winners.

## Privacy

Lock-screen content contains only invoice period, prize tier, and prize amount.
Invoice number, merchant, transaction ID, purchase amount, note contents, and
other accounting data are excluded.

## Idempotency

Each delivered notification is persisted under a deterministic local key
derived from period, governed candidate identity, selected tier, and amount.
Repeated refreshes must not notify the same result twice.

## Boundary

This runtime has zero formal-accounting-write authority. Manual refresh and
automatic catch-up wiring will share this service. Payout bookkeeping remains a
later Issue #13 slice.
