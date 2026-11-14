# Issue #13 — 4.20.24 Local Remittance Receipt Observation Preflight

4.20.23+481 is OWNER PASS/CLOSED. Official prize eligibility and start of the redemption window do not mean the bank has received a credit. The new source of evidence is an explicit user observation of a real bank credit and its effective date, not an MOF or bank API confirmation.

Evidence is keyed by exact local proposal identity, period, tier, amount, destination account and source SHA. The record is locally persisted, idempotent, revocable and invalidated by a changed authority or account. No bank credentials, statement screenshots or full bank account numbers are requested.

This only records user-observed information. It is not verified settlement, a redemption claim or auto-post authorization. Formal transaction write and account balance mutation remain **ZERO**. External bank evidence verification, posting idempotency and an explicit owner-accepted execution slice remain separate future gates. PR #45 stays Draft / OPEN / Merge HOLD.
