# P4.20.3 Owner Real-Device PASS → P4.20.4 Start

Date: 2026-09-10 (Asia/Taipei)  
Repository: `easonliu714/my_finance_app_public`

## Frozen predecessor authority

P4.20.3 Nationwide Official Registry owner validation is **PASS / CLOSED at product Gate**.

Frozen release-authority head:

`e5a81ab610da76c666e0993300d2a89dd5c033b6`

App/build validated on device:

- App version: `4.20.3+459`
- Android versionName: `4.20.3`
- Android versionCode: `459`
- PR #41 remains **Draft / OPEN / NOT MERGED**
- Merge Authority remains **HOLD**; this checkpoint does not authorize merge.

## Owner real-device evidence

The explicit nationwide Registry update completed end-to-end on device.

Observed stages included:

- download progress with downloaded MB / total MB / percentage / MB/s / ETA;
- SHA-256 / Registry stream validation progress with uncompressed MB / total MB / percentage / MB/s / ETA;
- V24 Registry install progress with installed rows / total rows / rows/s / ETA;
- final authority switch to Registry version `p4.20.3-fia-2026-09-09-b98874df3998`;
- official data date `2026-09-09`;
- coverage `全台公司／商業／分公司`;
- source `MOF_FIA_BGMOPEN1_ACTIVE_TAX_REGISTRY`;
- local official-detail lookup for seller tax ID `31655572` returned the FIA detail row, including official legal name `富達零售股份有限公司晶技門市` and parent seller tax ID `22853565`.

The owner switched to another app three times during the update. Returning to the app did not cancel the worker; processing continued and the Registry ultimately installed successfully.

## Non-blocking carry-forward finding

One UX regression was observed during background → foreground testing:

- only the SHA-256 / stream validation stage could return with a visually stale progress frame;
- the underlying validation worker continued making progress;
- download and V24 install stages did not show the same persistent visual-staleness symptom;
- the update still completed and installed correctly.

Classification: **NON-BLOCKING UX REGRESSION / CARRY FORWARD TO P4.20.4**.

The successor repair must not change:

- manifest/SHA authority;
- bounded streaming;
- canonical entity validation/order/uniqueness;
- V24 transactional install;
- LKG rollback;
- explicit-user-action-only Registry update;
- local-only Invoice Review lookup.

The first narrow P4.20.4 repair adds cooperative event-loop yielding during the CPU-heavy validation entity loop so foreground rendering/lifecycle work can obtain frames without changing hashed bytes or validation order.

## P4.20.4 successor

Successor branch:

`p4-20-4-merchant-decision-composer`

Branch base is the exact owner-validated P4.20.3 head above.

P4.20.4 Merchant Decision Composer is now **ACTIVE**.

Product objective: present three distinct merchant-identity choices during invoice review:

1. `此次辨識結果` — OCR / AI / QR result;
2. `既有正式商家` — user-facing confirmed MerchantBrand;
3. `官方登記資料` — official Registry legal/entity evidence, seller tax ID, source/date.

Required actions remain explicit user choices:

- `套用此次辨識`;
- `套用既有正式商家`;
- `依官方資料建立／綁定`.

Frozen semantic boundary:

`invoice literal != MerchantBrand != official legal name`

Selecting a candidate must never itself create a formal transaction. The accounting boundary remains:

`reviewed invoice → TransactionEntrySeed → editable draft → explicit Save → formal transaction`.

## Initial P4.20.4 implementation slice

The first successor slice contains:

- explicit three-way Merchant Decision Composer domain contract;
- no implicit/default candidate selection;
- official Registry candidate requires a second explicit merchant-binding confirmation;
- existing MerchantBrand remains separate from official legal name;
- every candidate selection preserves the invoice literal;
- composer selection cannot perform a formal transaction write;
- focused regression coverage for the above;
- cooperative SHA/stream validation yield regression for the owner-observed foreground-resume UX issue.

## Next Gate

1. exact-head Flutter analyze + focused tests;
2. full regression suite;
3. wire the pure composer contract into the invoice handoff UI without duplicating business logic;
4. prove the three visible candidate lanes and explicit actions on widget tests;
5. prove MerchantBrand / legal-name / invoice-literal separation;
6. prove merchant binding never bypasses review confirmation / editable draft / explicit Save;
7. advance P4.20.4 build/version only when the first user-visible vertical slice is ready for a new signed canary.
