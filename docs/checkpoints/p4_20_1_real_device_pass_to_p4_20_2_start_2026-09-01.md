# P4.20.1 Real-device PASS → P4.20.2 Start

## Frozen parent authority

- package: `4.20.1+454`
- exact head: `c8c10230748c4749ac59dd96ae79fb69368f58dc`
- PR #39: Draft / OPEN / NOT MERGED
- canonical CI #365 / run `33485777903`: PASS
- signed canary #11 / run `33485777958`: PASS
- owner real-device validation: PASS / FROZEN
- merge authority: HOLD

## P4.20.2 goal

Make the already-installed official business registry useful during invoice review itself:

`authoritative sellerTaxId → local official lookup → review-time corroboration → explicit mapping confirmation`

Registry data remains corroboration only. A registry HIT must never promote weak OCR evidence, silently overwrite invoice literal merchant text, auto-create a MerchantBrand, or create a transaction.

## R1 implemented

- new fail-closed `InvoiceRegistryCorroborationAuthorityPolicy`;
- authoritative QR seller identifier may enter registry lookup even when the legacy checksum does not pass, because QR provenance is the identity authority;
- Traditional Frozen OCR is eligible only when the parser accepted an exact `explicit_label` seller-tax source and checksum;
- contextual/header/positional weak OCR evidence cannot gain authority from the registry;
- `InvoiceCaptureReviewFlowCoordinator` performs corroboration after local recognition and before transaction handoff;
- official legal name and known formal MerchantBrand are added as review helper notices only; invoice seller-name literal remains unchanged;
- validation-subset provenance remains visible;
- registry exception/failure is non-blocking and produces no formal write;
- safe summary records eligibility/source/status/coverage without exposing unrelated accounting history.

## R2 required before device gate

1. Live multi-frame `positional_header_8digit_temporal_repair` authority must participate without falling back to weak single-frame semantics.
2. When the user edits sellerTaxId or switches OCR/QR ↔ AI source, any prior corroboration must be invalidated and resolved again from the new authority state.
3. Explicit AI sellerTaxId adoption must require global AI acknowledgement plus the governed strict non-QR seller-ID validation before registry lookup.
4. Existing confirmed MerchantBrand may be reused automatically; a new Brand↔Legal mapping remains explicit user confirmation.
5. Focused/full CI and signed `4.20.2` device gate required before owner validation.

## Safety invariant

`review → TransactionEntrySeed → editable draft → explicit Save → formal transaction`

No merge authorized.
