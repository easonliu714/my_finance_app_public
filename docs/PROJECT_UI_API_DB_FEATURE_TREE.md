# 記帳軟體 UI／功能／外部 API／SQLite 資料架構樹與完成驗證矩陣

> **CURRENT 2026-10-14 22:42:** 4.20.35 Back-to-Top OWNER PASS; new 4.20.36 P0 UI reattach Gate A code only / native Gate B HOLD. See latest appendix.

> **CURRENT 2026-10-14 20:11:** 4.20.35 CI failed two tests; focused widget viewport and strict version pin repair; cloud500 P0 still HOLD. Latest appendix controls.

> **CURRENT 2026-10-14 15:32:** 4.20.34 Flutter CI/Signed PASS, Owner cloud500 FAIL; 4.20.35+493 Back-to-Top UI CODE-only; P0 native reattach remains HOLD. Latest appendix controls.

> **CURRENT 2026-10-14:** 4.20.33 native background survives lock in Owner observation, completion >5min HOLD. 4.20.34 native stage visible after lifecycle resume SOURCE only; CI/Owner device pending. Latest appendix prevails over historical status lines.

> **CURRENT 2026-10-14:** Group UX 4.20.32 Owner PASS; cloud500 4.20.33 screen-off Worker mitigation CODE only and exact-head CI/DEVICE PENDING. Other cloud tiers targeted search next governed gate; earlier NEXT labels historical.

> **CURRENT 2026-10-14:** Backup Scope V9 4.20.31 OWNER PASS; 4.20.32 Account Group Balance Semantics CODE-only. Details in latest appendix; prior CURRENT/NEXT labels are historical checkpoints.

## NEXT CANDIDATE 4.20.30+488 — Issue #4 年度標題不截斷（2026-10-13）

```text
帳戶 / AccountDetailPage
 └─ SliverPersistentHeader(_AccountSummaryHeaderDelegate)
     ├─ min/max extent = MediaQuery.textScalerOf(context).scale(172)
     ├─ _CompactPeriodSummaryCard (YEAR)
     │   ├─ Line 1: full anchor.year + 年 label, fitted if needed
     │   ├─ Line 2: annual net monetary amount, independent from label
     │   └─ Line 3-4: yearly inflow/outflow as before
     └─ _CompactPeriodSummaryCard (MONTH) — same common rendering path
         ├─ Line 1: 05月/08月/10月; no duplicate year
         ├─ Line 2: monthly net
         └─ Line 3-4: monthly inflow/outflow
App services: existing accountDetailProvider -> summaryFor(year,month)
Storage: existing SQLite read-only accounting aggregator, NO ALTER TABLE,
         no new write, no migrated balance, no forced rounding or FX conversion.
Legacy issue4 month geometry remains exact RenderSliverList first-visible row.
Tests: static layout source regression + full Flutter analyze/tests,
       pending signed APK and owner narrow mobile/year label proof.
```

**Source Gate CODE=COMMITTED.** New release 4.20.30+488 / `issue-13-accepted-issue-4-summary-title-488`. `CI`, `SIGNED`, `OWNER_DEVICE` for 4.20.30 remain **PENDING** until separately verified on newest exact HEAD. 4.20.29 exact code HEAD `375ef1078dd6c21f8d1683260d8c497498362011` remains immutable DEVICE=OWNER PASS, and Issue #13 award page is unchanged by .30. Next Issue #4 group folding/liability/multicurrency still PLANNED, NOT automatically completed. PR #45 remains Draft/OPEN/Merge HOLD.

## CURRENT AUTHORITY — 4.20.29 Owner Device PASS / Next Issue #4

> 2026-10-13 22:08 Asia/Taipei。This supersedes outdated status snippets below. Accepted **CODE HEAD** `375ef1078dd6c21f8d1683260d8c497498362011`; Flutter CI [38402561190](https://github.com/easonliu714/my_finance_app_public/actions/runs/38402561190) SUCCESS and genuine Signed Canary [38402572785](https://github.com/easonliu714/my_finance_app_public/actions/runs/38402572785) SUCCESS, signed workflow artifact 11816709394. The current docs branch head can differ due to governance-only commits; don't misrepresent acceptance CI as applying to a modified later head. Owner supplied 4.20.29+487 Android evidence 22:03–22:04: award period help exterior & short selector/deadline, compact bank/e-wallet account transaction cards and on-scroll month summary. `DEVICE=OWNER PASS (stated combined gate)`; not evidence for other untouched issue DoD.

```text
[已驗收 4.20.29+487] Flutter Local-first App
 ├── [Issue #13]「我的」→ 統一發票中獎檢查
 │   ├── InvoiceAwardProductionPage → period selector Row:
 │   │   ├── Expanded Dropdown(periodLabel only, isExpanded)
 │   │   ├── 8 px spacer → independent '?' icon outside InputDecoration
 │   │   └── under Row: 兌獎資訊 statusLabel(now), updates with period
 │   ├── '?' → _showAwardHelp official source / privacy / PDF bottom sheet
 │   ├── Service: MOF official award acquisition, local matching, LKG,
 │   │   Android scheduler and optional notification (NO new service this release)
 │   └── Storage: local period source / SharedPreferences and governed
 │       transaction SQLite; no automatic formal income / no DB change
 └── [Issue #4]「帳戶」→ shared AccountDetailPage
     ├── bank CTBC 5445: 700 TWD balance; Year 2026 700;
     │   10月 200; existing +500 Aug / +200 Oct ledger items
     ├── iPASS Money: compact everyday purchases; month 05月 -1.87K;
     │   month 08月 -2.37K, annual -6.42K TWD; visible anchor updates
     ├── shared _CompactPeriodSummaryCard → observed yearly label '20...'
     │   → OUTSTANDING DISPLAY issue (requires full '2026年')
     ├── source-audit expansion in cards persists original identifiers
     └── no changes to financial transactions/current balances
[Next Gate] Issue #4 year title full visibility without ellipsis
 ├── existing UI: _CompactPeriodSummaryCard layout and pinned summary
 ├── no new service/API/store, preserve original summaryFor/year-month scope
 ├── Widget contract: 360px, large amount, scaled fonts, full 2026年
 ├── Flutter analyze/full tests, true Signed Canary, signed artifact
 └── Owner focused acceptance
[Subsequent] Issue #4 account-type collapsible grouping
 ├── first inspect current account list renderer and account.type taxonomy
 ├── bank/wallet vs credit/loan/investment currency and sign semantics
 ├── never combine mismatched currency and liability in fake net total
 └── DoD for group toggle/restart and grouping counts before implementation
[Still OPEN] Issue #13 external award/payout reconciliations and timing
 ├── Issue #13 origin describes 25th approx 16:00 but UI schedule 14:00
 │   → authority/owner decision required before scheduling behavior change
 ├── local POSTED is not proof of bank credit API receipt
 └── Do not duplicate income or retroactively backfill
```

Status distinctions: `CODE` / `CI` / `SIGNED` / `OWNER_DEVICE` / `MERGED_MAIN` are independent; 4.20.29 Owner device slice passed, PR #45 remains OPEN/DRAFT/MERGE HOLD, PR #46 CLOSED_NOT_MERGED, 18 pure issues OPEN. Screenshots here do **not** separately prove Sept 11→21→24 within-month scroll, Dec→Jan rollover, every account type, physical DB introspection or bank credit. Issue #4 and #13 parents remain OPEN while residual DoD is tracked. Sources: [PR #45 acceptance](https://github.com/easonliu714/my_finance_app_public/pull/45#issuecomment-6147506025), [Issue #4](https://github.com/easonliu714/my_finance_app_public/issues/4#issuecomment-6147519708), [Issue #13](https://github.com/easonliu714/my_finance_app_public/issues/13#issuecomment-6147521076).

---

> 更新：2026-10-13 16:55 Asia/Taipei。Repo `easonliu714/my_finance_app_public`，PR #45 active HEAD `43dfc02f5b78fa1900c7d83ba7b57d0b8888f5b2`。本次原始碼全文基準為使用者上傳的 **舊 HEAD `dec1c2d994143fe358058f11a38206e47bcac454` ZIP**；最新 4.20.28 五檔差異以 GitHub readback 為據，未將舊 ZIP 誤寫成最新 checkout。
> 狀態：`CODE` 原始碼存在，`TEST` 自動測試通過，`DEVICE` 實機通過，`HOLD` 未達 Gate，`CANDIDATE` 已 commit 但未驗證，`PLANNED` 缺實作。CODE != TEST != DEVICE != MERGED。

## 0. 真實執行架構（不是 SPC FastAPI）

```text
Android Flutter (lib/app.dart)
  └─ GoRouter (lib/routing/app_router.dart)
      └─ 五個底部分頁／對應子路由
          ├─ Flutter UI widgets -> Riverpod/provider/state
          ├─ Repository/Service -> sqflite on-device SQLite
          ├─ SharedPreferences -> 非帳務開關/小型設定/last-known-good cache
          ├─ Device camera/gallery/OCR, notification & Android scheduler
          └─ 受控官方 HTTPS/CSV/Gemini 外部查詢（依同意/權威）

正式 SQLite：ProductionDatabaseCoordinator → AccountRepository.instance.database
  └─ createCanonicalProductionV24Tables() → V23 → ... V13 等遞進 schema
非正式示範/legacy：AppDatabase (databaseVersion=1, books...) 不可和 V24 混同
````

## 1. 五分頁 UI/UX → 能力 → 存取鏈

```text
【帳戶】AccountPage [CODE，#4/#5/#6/#9 待全部 UAT]
 ├─ 帳戶型別、餘額、列表 → account_repository → accounts/transactions
 ├─ AccountDetailPage → period summary/ledger tiles → transaction ledger
 │   ├─ 4.20.28 可見交易年/月錨點 [COMMITTED，CI FAIL，DEVICE ?]
 │   └─ 4.20.28 精簡交易卡／可展開稽核 [COMMITTED，CI FAIL]
 ├─ Debit card pending/settlement → debit_card_* → debit_card_profiles/settlements/audits
 └─ Stored value/eWallet reload → wallet_top_up_* → profile/suggestion/execution/audit
【計畫】RepaymentPlanPage / CreditCardInstallmentPreviewPage [CODE，full UAT?]
 ├─ 信用卡分期、帳單、最低應繳／循環利息 → plan repositories / SQLite installment family
 ├─ 應繳與提醒 → plan_due_summary_service/local_notification_service
 └─ 貸款提前還款模擬 [OPEN #7]
【首頁】DashboardInvoiceEntryShell / DashboardPage [CODE]
 ├─ 總資產、收支、快速記帳／交易草稿 → transaction_entry_page → canonical transactions
 ├─ 發票、雲端、商品照片、語音快速入口 → invoice/product/voice feature flows
 └─ 使用者自訂捷徑 / local order [OPEN #14]
【報表】LedgerDetailPage / dashboard reports [CODE]
 ├─ 期間損益／分類／交易列表 → account+transaction repository
 └─ 統一發票中獎檢查 InvoiceAwardProductionPage [#13]
      ├─ 官方期別/獎號與雲端獎 LKG → official acquisition+PDF index/cache
      ├─ 背景更新與通知 → scheduler / notification_runtime
      ├─ 4.20.28 「？」說明精簡 [COMMITTED，CI FAIL，DEVICE ?]
      └─ POSTED 收款確認 → posted stable ID → formal transactions (explicit consent)
【我的】MyPage [CODE；settings consolidation open]
 ├─ 商家／官方統編更新與查詢 → merchant registry services → business_registry_*
 ├─ Gemini BYOK／受控上傳、隱私設定 → secure settings + external AI APIs
 ├─ 備份/可讀匯出/還原 → backup/* (local files + SQLite)
 ├─ 通知偏好、行事曆更新、資料安全 [#8 #12 #18 #19]
 └─ App build/version/營業人資料有效期 → app_build_metadata + registry snapshots
```

## 2. 現存子流程/隱藏功能不等於正式完成

```text
Invoice Capture → camera/gallery/OCR → frozen review → editable transaction seed → explicit Save
Cloud Invoice Lab → CSV + review / conflict / enrichment / promotion (lab/route guarded)
Product Photo → capture / Gemini consent / candidate review → transaction draft
Voice → OS transcript / editable parse → transaction draft
Merchant Registry → official acquisition → staged snapshot/validated integrity → read-only identity lookup
Backup → export/restore preview → explicit commit and security boundary
```
- `lab/` 程式或路由存在不代表用戶可在正常五分頁操作。
- Gemini/官方網路資料皆為外部來源；**本 app 並無 SPC 專案的 FastAPI/PostgreSQL**。不可憑 external client 存在宣稱真實 API 全程成功。
- 交易正式寫入與操作後通知必須區分；金融資料的 `POSTED` 是本地帳本狀態，不證明銀行獨立資料。

## 3. 正式 DB DDL family（此處是原始碼定義，不是當日手機 live PRAGMA）

```text
SQLite my_finance_app.db [ProductionDatabaseCoordinator; canonical schema v24]
├─ 核心帳本 [AccountRepository / TransactionRepository authority]
│  ├─ accounts / transactions / merchants / canonical account models
│  └─ production_migration_markers (遷移控制，v13)
├─ 雲端發票 [v13–v16]
│  ├─ cloud_invoice_drafts / cloud_invoice_metadata_links
│  ├─ cloud_invoice_operations / cloud_invoice_before_images / cloud_invoice_audits
│  ├─ cloud_invoice_draft_promotions / cloud_invoice_detail_enrichments
│  └─ UNIQUE operation_key / rollback_token：防重複與回復
├─ 簽帳卡 [v17–v19]
│  ├─ debit_card_profiles / debit_card_settlements
│  ├─ debit_card_authorization_audits
│  └─ debit_card_settlement_confirmation_audits
├─ 台灣工作日 [v17]
│  └─ taiwan_business_calendar_days
├─ 儲值／電子錢包 [v20–v21]
│  ├─ wallet_top_up_profiles / wallet_top_up_suggestions / wallet_top_up_audits
│  └─ wallet_top_up_executions
├─ 商家身分與統一編號 [v22–v24]
│  ├─ merchant_brands / merchant_brand_aliases / merchant_legal_entities
│  ├─ merchant_branches_or_outlets / merchant_brand_legal_links
│  ├─ merchant_identity_observations
│  ├─ business_registry_snapshots / business_registry_entities
│  ├─ business_registry_negative_lookups
│  └─ business_registry_official_details (v24：官方完整欄位 JSON，與交易明細分離)
└─ 警示：AppDatabase._onCreate 的 books/budgets/recurring_rules ... 為 v1 老路徑；
       不可不經 repository active-open graph 查證就列為 v24 current physical tables
```

## 4. DDL 原始碼逐檔索引

- `lib/database/production_schema_v13.dart`：`merchants`, `production_migration_markers`, `cloud_invoice_drafts`, `cloud_invoice_metadata_links`, `cloud_invoice_operations`, `cloud_invoice_before_images`, `cloud_invoice_audits` （DDL_ONLY）
- `lib/database/production_schema_v14.dart`：`cloud_invoice_draft_promotions` （DDL_ONLY）
- `lib/database/production_schema_v15.dart`：`cloud_invoice_detail_enrichments` （DDL_ONLY）
- `lib/database/production_schema_v17.dart`：`debit_card_profiles`, `debit_card_settlements`, `taiwan_business_calendar_days` （DDL_ONLY）
- `lib/database/production_schema_v18.dart`：`debit_card_authorization_audits` （DDL_ONLY）
- `lib/database/production_schema_v19_confirmation_tables.dart`：`debit_card_settlement_confirmation_audits` （DDL_ONLY）
- `lib/database/production_schema_v20_wallet_top_up_tables.dart`：`wallet_top_up_profiles`, `wallet_top_up_suggestions`, `wallet_top_up_audits` （DDL_ONLY）
- `lib/database/production_schema_v21_wallet_top_up_execution.dart`：`wallet_top_up_executions` （DDL_ONLY）
- `lib/database/production_schema_v22_merchant_identity.dart`：`merchant_brands`, `merchant_brand_aliases`, `merchant_legal_entities`, `merchant_branches_or_outlets`, `merchant_brand_legal_links`, `merchant_identity_observations`, `business_registry_snapshots`, `business_registry_entities`, `business_registry_negative_lookups` （DDL_ONLY）
- `lib/database/production_schema_v23.dart`：`business_registry_entities` （DDL_ONLY）
- `lib/database/production_schema_v24.dart`：`business_registry_official_details` （DDL_ONLY）

## 5. UI/Service/DB/Issue crosswalk 與驗證矩陣

| 使用者入口 | Canonical source / Repository | 資料/外部 authority | Issue | 工程 / 測試 / 實機 |
|---|---|---|---|---|
| 帳戶列表/明細 | account_page / account_detail_page / account_repository | accounts, transactions | #4 #5 | CODE；4.20.28 committed / CI FAIL / Device? |
| 簽帳卡 | debit_card_repository / debit_card_settlement_* | debit_card_* | #6 | CODE；full lifecycle UAT? |
| 儲值 | wallet_top_up_* | wallet_top_up_* | #9 | CODE；full flow UAT? |
| 貸款/分期 | plan/* | installment/plan models | #7 | CODE；prepay simulation? |
| 語音快速記帳 | voice_transaction_entry_page | transcript → transaction draft | #28 | CODE；full device? |
| 發票 OCR | invoice_* capture/review | original invoice / Gemini guarded | #22 | CODE；E2E privacy gate? |
| 發票獎金 | invoice_award_production_page + formal_income_posting_service | official MOF dataset + local transactions | #13 / PR45/46 | 4.20.26 POSTED DEVICE PASS；4.20.28 CI FAIL |
| 商家統編 | merchant/business_registry_* | business_registry_* full details snapshot | #20 CLOSED | CODE；snapshot/readback gates individually |
| 商品拍照 | product_capture_page / gemini_product_recognition_client | candidate → editable draft | #16 #17 | PARTIAL code; full camera/crop/retention Gate? |
| 我的/備份 | my_page / backup/* | user-managed backup, settings | #8 #12 #18 | CODE；encryption OPEN |
| 台灣行事曆 | taiwan_business_calendar_package_service | taiwan_business_calendar_days | #19 | CODE；annual-update end-to-end? |
| 首頁捷徑 | dashboard / root shell | SharedPreferences local setting | #14 | OPEN; no new 4.20.28 gate |

## 6. 外部 API 權限/資料流樹

```text
OFFLINE FIRST (預設)
├─ SQLite read/write：正式帳本／帳戶／商家；需要明確 Save 或正式金融動作授權
├─ Local KV：設定/選擇/快取/通知開關；不可當成實際銀行入帳權威
└─ Device media：camera/gallery/OCR/通知排程：依 Android 版本及權限
EXTERNAL ONLY WHEN AUTHORIZED
├─ Ministry of Finance: 官方一般獎號＋雲端專屬獎資料，validated LKG, fail-closed
├─ 官方統編資料發佈/查詢：版本/SHA 校驗後 staged install, 交易不覆寫
├─ Gemini BYOK: user consent and secure key, candidate-only
├─ 雲端發票官方/CSV：lab vs production auth boundary 必須分別驗證
└─ 台灣官方行事曆：官方 package + 手動 CSV fallback (#19 DoD 未閉環)
```
所有外部 URL/method/timeout 是否正確，由當前 Client source 各路徑與正式網路 UAT 另表核對；本次未執行 HTTP live requests，**不要虛構 endpoint**。

## 7. 應新增到專案狀態表的遺漏功能與技術債

1. PR #45 與 #46 重複 auto-refresh 功能：比較 active-import consumers 和 commit ancestry，決定 #46 是已被覆蓋的歷史候選還是有未合併改動；完成前 KEEP。
2. Issue #4 4.20.28 僅解帳戶細節可見錨點/精簡，不含帳戶清單分組與 liability/multicurrency 全面 UAT。
3. Issue #13 外部銀行證據不可由本地 `POSTED` 推定；獎金 eligibility / receipt / new formal write 三個 Gate 必須分離。
4. 正式 SQLite v24 與歷史 AppDatabase v1 同名 DB 的開啟關係/物理 table list，須在受控實機 PRAGMA sqlite_master 讀取後封存。
5. Merchant registry official full details 應是獨立 versioned cache，交易只綁 seller tax/merchant identity，不把官方所有欄位逐筆複製。
6. 快速新增與常用 selector、商品圖片裁切、設定統一入口、行事曆年度更新、backup+encryption、全域通知設計各已有 Issue，不另開重複父級 Epic。
7. Live PR HEAD 與本輪上傳原始碼 ZIP 相差五個 4.20.28 commits，因此任何新程式碼變更都要先 fresh checkout；本檔 source inventory 不是最新完整快照。

## 8. 防重工前置 Gate

- 任何新功能先填 `Feature ID → 現有五分頁 UI → route/widget → service/repository → 現有 SQLite table/KV → 外部來源 → Open Issue/PR → 已驗 Gate → 尚缺 Gate`。
- 「新增按鈕」不等於「完整 E2E」；「SQL DDL」不等於「手機實體 table」；「PR CLOSED」不等於「main MERGED」。
- 修改財務資料之前對照 `db.transaction<bool>`、`ConflictAlgorithm.abort`、可逆回滾、來源 SHA、用戶 consent、idempotency。
- 每次快照保留實際提交 HEAD/Blob、live CI run、owner device evidence、未驗證清單；不以舊 ZIP 覆蓋新 PR。

---
## 2026-10-13 活躍來源與去重補充

1. 目前唯一 active 發票中獎 runtime PR 是 **#45**；舊自動更新候選 **PR #46 已 Closed/NOT MERGED**。禁止由 #46 再導入第二個 SharedPreferences 自動更新狀態機或 process mutex。Canonical 入口為 `lib/app.dart` → `InvoiceAwardAppLifecycleCoordinator` → `InvoiceAwardRuntimeScheduler` → `InvoiceAwardCanonicalAutomaticRefreshRunner`，手動頁面與自動 runner 共用 `InvoiceAwardRefreshProcessGate`；Android native wake/notification 按現有 Gate 管理。
2. 4.20.28 在現行 Branch 上已 COMMITTED 的帳戶詳情可見錨點與發票頁『？』說明仍只屬 CODE。Flutter exact-HEAD CI run `38356246784` 失敗（1892 PASS / 12 FAIL），新版 Signed Canary 尚未產出。不得將 CODE 升為 TEST 或 DEVICE。
3. 版本契約待修：`lib/features/invoice/lab/private_cloud_invoice_lab_config.dart` 仍宣告 `4.20.27+485`；多個測試仍 pin 舊版/phase。另一 UI 測試需要先點按「開獎期別與官方來源說明」後才驗證『大型 PDF』的長篇說明。不應退回常駐顯示長文。
4. 正式外部銀行入帳和本機 `POSTED` 不可等價；NT$500+NT$200=NT$700 既有已記帳交易不得 background backfill、重複寫入或為修測試而移除。
5. 任何新功能必先填「五分頁入口 → UI Widget/Route → active Service/Repository → SQLite v24/SharedPreferences 實體 → 外部 authority → Owner Issue → CODE/TEST/DEVICE/RELEASE Gate」，找不到才新增新模組/Issue。不得因 SQLite DDL 声明等於手機真實 PRAGMA 已驗。

## 4.20.28 操作介面一致性／測試關係更新（2026-10-13）

```text
[Issue #13] 統一發票中獎檢查頁 / InvoiceAwardProductionPage
  ├─ 開獎期別 DropdownButtonFormField
  │   ├─ UI: isExpanded=true (6.4 px overflow root cause fix, commit cf7a7067)
  │   └─ [？] 開獎期別與官方來源：財政部限定、不上傳發票或記帳內容、大型 PDF、更新限制
  ├─ 自動更新官方獎號 Switch + [？] → RuntimeScheduler / native wake (原契約不變)
  ├─ 中獎結果通知 Switch + [？] → NotificationRuntime (原契約不變)
  ├─ 中獎獎金自動記帳準備 / Account + [？] → Readiness + Explicit Receipt + Explicit Post
  └─ 授權更新並檢查既有交易 Button + [？] → MOF official acquisition / local candidate matching
[Issue #4] 所有帳戶共用明細卡片 → 來源稽核可展開 / render geometry 可見交易錨點
[DB] SQLite formal transactions + local Preferences / cached official candidates
  └─ 本輪沒有 schema 變更，沒有新增/更動正式交易，POSTED NT$500+200=700 凍結
```

**完成標記不得越級：** 上述 Dropdown/UI 本輪 CODE=PASS（實際 GitHub commit），分析/全測試 TEST=PENDING、Signed Canary/簽章 RELEASE=PENDING、Owner DEVICE=PENDING。功能樹新修正以 4.20.28+486 為對象，測試 `invoice_award_check_route_test.dart` 改用「預設隱藏，點『？』後顯示」並保留官方來源／不外傳資訊檢查；不要改回主畫面長篇說明。主帳本正式收入使用者逐次明確授權、歷史無自動補登、正式交易冪等未被此次修補觸碰。

## 4.20.28 Signed release phase vs UI／Service／DB authority (2026-10-13)

- `lib/app_build_metadata.dart` release `phase` is `issue-13-award-help-issue-4-account-geometry-486`. This is a combined owner-authorized 4.20.28 slice with Issue #13 Signed Canary as the release authority: `issue-13-` prefix mandatory, suffix names the Issue #4 cross-account list/scroll Geometry work.
- Production UI functionality and API/storage path remain unchanged by the phase fix. `InvoiceAwardProductionPage` retains compact '?' help and explicit bank receipt/formal income consent; `AccountDetailPage` retains expandable provenance and real visible month/year anchoring. Data authority remains local SQLite formal transactions, official MOF candidate evidence, bounded SharedPreferences states; none of these records were modified by release metadata patch.
- Tests bound to exact phase updated: `test/p4_20_5_release_authority_test.dart`, `test/issue_13_payout_bookkeeping_release_contract_test.dart`, `test/issue_13_invoice_award_notification_release_contract_test.dart`. The signed workflow itself remains unchanged and enforces its original `issue-13-` check.
- State tracking: CODE=committed; TEST=await new exact-head full suite; SIGNED_ARTIFACT=await new true canary; DEVICE=not yet authorized. Old code HEAD `36310c24445d440ecfdd93538660ae821c046199` Flutter CI [38384304123](https://github.com/easonliu714/my_finance_app_public/actions/runs/38384304123) SUCCESS, but its Signed Canary [38384311754](https://github.com/easonliu714/my_finance_app_public/actions/runs/38384311754) FAIL release identity; future HEAD cannot reuse either result as final release authority.

## Owner 實機 PASS 後的 4.20.29 UI 功能樹（2026-10-13）

```text
[原已驗收 4.20.28] Issue #13 統一發票中獎檢查
  ├─ 開獎期別與官方來源「？」底部說明 → DEVICE=OWNER PASS
  ├─ 自動更新官方獎號 Switch + 「？」 → DEVICE=OWNER PASS (UI)
  ├─ 中獎結果通知 Switch + 「？」 → DEVICE=OWNER PASS (UI)
  ├─ 自動記帳準備 / 銀行選擇 / 匯款確認 / 候選開關 + 「？」 → DEVICE=OWNER PASS (UI)
  ├─ 官方資料更新與既有交易比對 → 115-05-06、115-07-08 兩期 UI 顯示證據
  └─ 重要限制：這些 screenshots 不能取代銀行收款/正式 SQLite transaction 實機稽核
[後繼 4.20.29] Issue #13 期別選擇器微調
  ├─ UI DropdownButtonFormField<String> / lib/features/invoice/invoice_award_production_page.dart
  │   ├─ DropdownMenuItem.child = Text(option.periodLabel) — 只顯示「115年07-08月」
  │   ├─ 下方 Text('兌獎資訊：${_selectedPeriod.statusLabel(now)}')
  │   ├─ [？] 原官方來源、PDF、隱私保護底部說明維持
  │   └─ isExpanded:true 繼續防止狹窄手機 RenderFlex overflow
  ├─ Domain: lib/features/invoice/invoice_award_period_catalog.dart
  │   ├─ periodLabel / statusLabel(now) 沿用原邏輯，不改開獎/兌獎判斷
  │   └─ 期別選定仍只依原 period.id 與 canCheckAt(now) 控制
  ├─ Widget Regression: test/invoice_award_check_route_test.dart
  │   └─ Dropdown 只包含期別；期限只在下方 status；點開 ? 長文仍可見
  ├─ API/External MOF: UNCHANGED
  ├─ Storage SQLite / SharedPreferences: SCHEMA and business data UNCHANGED
  └─ Release: 4.20.29+487 / issue-13-award-period-selector-487
```

**驗證分層**：4.20.28 的 Issue #13 介面 DEVICE=OWNER PASS；4.20.29 CODE=COMMITTED、TEST=NEW EXACT HEAD PENDING、SIGNED APK=PENDING、DEVICE=PENDING。其他 Issue #4 帳戶明細 Gate 在此次截圖沒有獨立實機證據，不能隨發票 Gate 自動關閉。原 POSTED NT$500+200=700 一律凍結，無新交易或背景補登。PR #45 Draft/Merge HOLD。

## 4.20.29 Flutter 公開 Widget API 測試治理（2026-10-13）

- Award Check period dropdown 選項（production）：`DropdownMenuItem(child: Text(option.periodLabel))`，下方 `Text('兌獎資訊：${_selectedPeriod.statusLabel(now)}')`，選擇期別與官方來源/API/DB/POSTED 全不變。
- Regression 測試（`test/invoice_award_check_route_test.dart`）：不得在 `DropdownButtonFormField<String>` widget 上直接讀不存在的 `.items` getter；改為 `tester.tap(find.byKey(Key('invoice_award_period_selector')))` 後實測 popup 內短期別文字，且主視窗維持「兌獎資訊」獨立顯示。新增 Widget test 與原「？」內容 test 獨立。CI 38400071955 的 first analyzer error 已用正式 commit e009331a420cceccb5a3286394974aa3b4e20a44 修補，下一個 CODE≠TEST Gate 以 latest HEAD 為準。
- No changes to MOF acquisition endpoint, active Award Domain catalog, SharedPreferences persistence, SQLite transaction schema, current Posted ledger credit idempotence, background scheduling or separate consent. 4.20.28 Award UI=OWNER PASS；4.20.29 CODE=COMMITTED/TEST=PENDING/DEVICE=PENDING，PR #45 MERGE HOLD。

## 2026-10-13 4.20.29 並排問號／下一個 Issue #4 實機 Gate 功能樹

來源分層與對應狀態：

    五分頁中的「我的」→ 統一發票中獎檢查（Issue #13）
      └─ InvoiceAwardProductionPage（UI CODE=COMMITTED / 4.20.29 TEST=WAIT）
          ├─ period_row / invoice_award_period_selector_row
          │   ├─ Expanded/DropdownButtonFormField（isExpanded=true；選單文字只有 periodLabel）
          │   ├─ SizedBox(width=8)
          │   └─ 問號 IconButton（OUTSIDE InputDecoration，不佔 dropdown suffixIcon）
          │       └─ onPressed → _showAwardHelp → 官方來源／隱私／PDF Bottom Sheet
          ├─ 兌獎資訊：沿用 selectedPeriod.statusLabel(now)，獨立下方顯示
          ├─ period.id / canCheckAt(now) / onChanged：不改
          ├─ API：Official MOF acquisition + PDF index / LKG → 不改
          └─ Storage：SQLite 正式交易 + SharedPreferences 批次快取 → 不改 schema / 不寫正式交易

    五分頁中的「帳戶」→ 全帳戶共用 AccountDetailPage（Issue #4）
      ├─ Transaction card compact 摘要（已存在於 4.20.28 CODE）
      ├─ 展開「來源／稽核資訊」保留 ET/FX/SHA/來源 ID
      ├─ RenderSliverList 真實可見交易錨點 → period YYYY-MM
      ├─ Paired summary 左 2026年、右 09月 → 相同 period 原子更新
      └─ Release 4.20.29 不新增帳戶 service、DB、資料讀寫
          └─ 綁定本輪 Owner real-device Gate（BANK + iPASS Money，same-month scroll、month/year rollover、reverse scroll、expand long card）

Testing／版次：
- test/invoice_award_check_route_test.dart 新增 360px 手機寬度布局與 tooltip 開啟回歸：幾何不重疊、按鈕在 InputDecorator/Dropdown 外、可開 Help Bottom Sheet。
- 4.20.29+487 release phase 仍為 issue-13-award-period-selector-487，source/test/docs 已實際提交，完整 Flutter Analyze/full tests/debug APK、true Signed Canary Validate/BuildInspect 和 Owner device Gate 未過前標 PENDING。
- Issue #4 現行 code 已有 UI；本輪只將其原本未完成的 Owner Gate 併入 .29，未擴張到帳戶分類、負債／多幣別計算；不能從本次截圖推斷全部帳戶原 DoD 通過。
- Frozen：原 POSTED NT$500+NT$200=700；不得背景補登、重複收入、取消人工獨立確認。PR #45 保持 OPEN/DRAFT，Merge HOLD。

## 2026-10-13 22:32 Owner 4.20.29 PASS 與 4.20.30 共用帳戶摘要下一 Gate

    Owner 4.20.29+487 DEVICE=PASS (limited evidence)
      ├─ 我的 → InvoiceAwardProductionPage
      │   ├─ 開獎期別僅 115年07-08月 → UI DEVICE PASS
      │   ├─ 期別框外右側獨立 [？] → UI DEVICE PASS
      │   └─ 下方兌獎資訊（至 2027-01-05）→ UI DEVICE PASS
      └─ 帳戶 → AccountDetailPage
          ├─ 一卡通 Money 2026/05、2026/08 精簡卡片 → DEVICE PASS
          ├─ 真正月份跟隨可見明細 → DEVICE PASS (這兩月份樣本)
          ├─ 中國信託 5445 本機餘額 700 TWD/既有獎金 +200、+500 → UI observed
          └─ 左側年份標題顯示 20... → RESIDUAL FAIL / Next P0

    4.20.30+488 CODE IMPLEMENTED / new exact-head TEST=PENDING
      ├─ UI lib/features/account/account_detail_page.dart
      │   └─ _CompactPeriodSummaryCard: 年／月 label 與 net 分行
      │       ├─ summary.label → FittedBox(BoxFit.scaleDown)，不得 ellipsis
      │       ├─ summary.net → 分開 FittedBox，顯示較長負值
      │       └─ inflow / outflow → 保留正常單行省略號
      ├─ Service / Repository / Date Anchor / API → NO CHANGE
      ├─ DB / SQLite Formal Ledger / SharedPreferences → NO CHANGE
      ├─ Test test/issue_4_issue_13_4_20_28_ux_contract_test.dart
      │   └─ 只檢查年份標題本身不可 ellipsis，不錯把 inflow/outflow 當標題
      └─ OWNER Gate pending: 一卡通 Money 年 2026年 完整、負值 TWD、銀行、
          05月/08月切換不漂移、跨月跨年與大字級（本輪未提供充分證據）

- 4.20.30 第一輪 Flutter CI 38412520575 跑 1906 PASS/1 FAIL，單一 static-test 範圍錯誤已修復並提交，不代表新版最新 HEAD Flutter CI/Signed Canary 已 PASS；完整 signed APK 和新的 Owner device Gate 仍待驗。
- 既有正式收入 NT$500 + NT$200 = NT$700 不改、不回填；Issue #4 帳戶語意與 #13 發票授權保持原先邊界。PR #45 DRAFT／OPEN／MERGE HOLD，#46 CLOSED_UNMERGED。

## 2026-10-14 00:37 完整備份 P0 回歸與 Scope V9 架構對照

    我的 → 完整備份／完整還原
      ├─ 「建立完整備份」 / BackupMigrationActionService.createAndShareFullBackup
      │   └─ FullBackupService.writeFullBackupFile
      │       ├─ FullBackupScope.inspect(sqlite_master) fail-closed
      │       │   ├─ Scope V8 受管使用者商家身分資料
      │       │   └─ Scope V9 新增 expense_categories (使用者自訂/封存分類)
      │       ├─ FullBackupService.buildFullBackupEnvelope
      │       │   ├─ metadata.backup_scope_version = 9
      │       │   ├─ data.expense_categories (row IDs, name, sort, archived)
      │       │   └─ 其餘使用者帳戶/交易/商家資料保持原受管集合
      │       └─ SharePlus 系統分享面板（前提：完整性 PASS）
      ├─ 「完整還原來源」 → FullRestorePreviewService
      │   └─ Scope V2–V8 各舊清單驗證；V9 缺分類陣列要 FAIL
      └─ 「完整還原」 → FullRestoreServiceV8（保留歷史入口）
          ├─ Scope < V8 legacy normalization ONLY
          ├─ 明確 RESTORE 確認與來源驗證
          ├─ 建立預還原完整備份快照
          └─ SQLite transaction 中 ensureExpenseCategorySchema(txn)
              ├─ 可安全 materialize 原本 lazy expense_categories
              ├─ 受管表刪除／重建／列數校驗／參照稽核
              └─ 任一失敗 Rollback，不得漏掉資料欄位

    分類 / ExpenseCategoryRepository（既有）
      └─ ensureExpenseCategorySchema(db)
          ├─ CREATE TABLE expense_categories（既有動態建表）
          └─ 自訂分類/封存設定/排序由使用者管理，必須可被完整備份

- 2026-10-14 Owner 4.20.30 帳戶年度摘要 Android UI Gate 局部 PASS：一卡通 Money 2026年及 08月/09月欄位完整顯示，中國信託 +500、+200 本地記帳仍在；不替代跨年、所有類型或完整帳戶 DoD。
- P0 實機回歸錯誤原文「檔案操作失敗：未知資料表：expense_categories」，源於完整備份 Scope V8 漏列已建立的使用者資料表，**不是可忽略的快取**。本次 Scope V9 及測試已提交，SQLite production schemaVersion=24 不變；沒有清空使用者資料、沒有改記帳紀錄，也沒有解除 fail-closed。
- 4.20.31+489 新 CODE=COMMITTED，TEST=NEW EXACT HEAD PENDING，SIGNED= PENDING，DEVICE= PENDING。真實實機還原具有覆寫性，必須使用隔離測試資料庫模擬，禁止把生產手機資料當測試還原目標。Issue #18 備份稽核 Roadmap/ Issue #4 UI / Issue #13 發票權限各獨立追蹤，不因同一 PR 內容混合而假定全完成。

## 2026-10-14 4.20.31 Owner Backup PASS → 4.20.32 分組語意架構樹

```text
[4.20.31+489 OWNER DEVICE PASS（本次回報）]
  我的 → 完整備份／完整還原
    ├─ FullBackupScope V9 / FullBackupService
    │   └─ expense_categories user-owned rows + original managed tables
    └─ FullRestoreServiceV8 / FullRestoreService
        ├─ Scope V8 historical manifest retained
        ├─ Scope V9 schema materialize within SQLite transaction
        └─ Fail-closed unknown tables and rollback remain mandatory
  CI 38433579674 = SUCCESS / TRUE Signed Canary 38433592413 = SUCCESS
  ※ 完整加密、所有歷史跨版災難復原 ≠ 本次實機 PASS；Issue #18 remains OPEN

[4.20.32+490 OWNER UI Gate — NEW CODE COMMITTED / CI PENDING]
  帳戶（AccountPage / Issue #4）
    ├─ AccountListProvider / AccountDetailProvider（既有，不修改）
    ├─ _groupAccounts(items) by AccountType.values（既有）
    ├─ _collapsedTypes、全部展開／點類型收合（既有）
    ├─ _AccountSummaryCard
    │   └─ reference amount heading + explanatory caption（NEW）
    ├─ _AccountTypeSection
    │   ├─ original groupTotalTwd = sum(currentBalance * defaultRateToTwd)
    │   │   └─ COMPUTATION UNCHANGED；非淨資產／非真實 FX
    │   └─ NEW AccountGroupBalanceSemantics
    │       ├─ cash/bank/debit/stored/eWallet/other → 帳面餘額合計非淨資產
    │       ├─ creditCard → 帳面餘額非待繳款／可用額度
    │       ├─ loan → 帳面餘額非未償本金
    │       ├─ investment → 帳面餘額非即時市值／報酬
    │       └─ non-TWD → 內建參考匯率（非即時）文字提示
    ├─ Individual Account Record / Account Detail → UNCHANGED
    ├─ API / external → NONE NEW
    ├─ SQLite canonical production schema v24 / Backup Scope V9 → UNCHANGED
    └─ test/account_group_balance_semantics_test.dart → pure text-semantics tests

Other modules and statuses:
  Issue #13 invoice award official sync, receipt authority, POSTED NT$500 + NT$200
      → no implementation change; must stay explicit-only income write, no backfill
  Issue #18 SQLite encryption/schema freeze → FINAL ROADMAP / NOT STARTED
  4.20.32 Flutter Analyze/full tests/Debug APK/true Signed Canary
      → PENDING (exact HEAD only)
  PR #45 OPEN/DRAFT/MERGE HOLD; PR #46 CLOSED_UNMERGED
```

驗收限制：分類名稱、外幣參考匯率及信用/貸款/投資帳戶只是 read-only UI 文字澄清；**並未重新計算資產負債、匯率或帳戶餘額**。Owner 4.20.31 備份/還原成功是該流程的實機證據，不足以封閉 Issue #18 所要求的加密與全部 cross-version Gates。最終狀態需以最新 GitHub HEAD／測試／實機紀錄為準。

## 2026-10-14 4.20.32 DEVICE PASS → 4.20.33 雲端 500 原生 SHA 中斷 Gate

```text
4.20.32+490 OWNER DEVICE PASS / CI+SIGN SUCCESS
  帳戶管理 → AccountPage
    ├─ 現金群組已顯示 -148 TWD；可開合
    ├─ 銀行群組已顯示 700 TWD / 2 帳戶；可開合
    ├─ 信用卡群組已顯示 -75 TWD / 語意「非待繳款或可用額度」
    ├─ 對應 ref-based static FX / borrowed-equity warning → CODE
    └─ 一般 account/ledger/backup Scope V9 → 原架構保持；未重新算金額
  Exact PR 2c90c14eccbd43771db795420aa9774389854090
  Flutter CI 38442351717 SUCCESS / True Signed Canary 38442361870 SUCCESS

4.20.33+491 CODE COMMITTED / EXACT-HEAD CI & SIGNED & DEVICE PENDING
  我的 → 統一發票中獎檢查 → CloudAwardForegroundAcquisition
    ├─ 官方 publication 4 條 _sorted_ PDF links → unchanged
    ├─ official CloudAwardArtifactDownloader (streamed + full SHA) → unchanged
    ├─ CloudAwardPdfCache / LKG → unchanged and fail closed
    ├─ cloud-500 exact 47 candidate universe → already EXISTING
    │   ├─ >=120 MiB (owner 128.9MB): PDF structure probe + source SHA
    │   ├─ PlatformPdfCandidateWorkerService Android API 35+ :platform_candidate_worker
    │   │   ├─ Android FGS dataSync + new bounded CPU PARTIAL_WAKE_LOCK (max 30min)
    │   │   ├─ SHA256 FULL_SOURCE on already persisted official PDF (MUST PASS)
    │   │   ├─ PdfRenderer sorted page binary search (AFTER hash) no full 87000 page parse
    │   │   ├─ per-candidate matched page proof / candidate universe SHA
    │   │   └─ finally release wake lock / stop foreground service
    │   ├─ PdfTextPlugin PID liveness + new diagnostic ApplicationExitInfo reason
    │   └─ died worker => FAIL (no candidate authority promotion), preserve old LKG
    ├─ cloud-800  : current complete-index builder (100000 row PDF)
    ├─ cloud-2000 : current complete-index builder (16000 row PDF)
    └─ cloud-1000000 : current complete-index builder (30 row PDF)
         └─ NEXT P1 candidate-scoped sorted-page search, NOT YET ENABLED

  Related Dart: invoice_award_cloud_candidate_scope.dart
  Android Java/Kotlin: PlatformPdfCandidateWorkerService.kt, PdfTextPlugin.kt
  AndroidManifest: WAKE_LOCK normal permission / FGS dataSync
  Tests: invoice_award_cloud_lifecycle_contract_test.dart; original candidate/official parity
  Data: SQLite / formal transaction / POSTED 500+200 / direct bank API → NO CHANGE
```

Owner 2026-10-14 approximately 08:08–08:17 +08 screenshot reports `CLOUD_AWARD_CANDIDATE_WORKER_PROCESS_DIED_PLATFORM_SOURCE_SHA256` at existing platform SOURCE SHA gate, **before actual PDF candidate search**. Screen lock correlates but reason unknown until reliable OS exit evidence. PDF raw structure diagnostic `raw_candidate_hits=0/47` is only compressed raw bytes visibility and cannot determine true PDF award membership. Three other award tiers show old LKG full index; P1 direct lookup must preserve official SHA, completeness and negative-proof semantics, parallel to comprehensive fixture parity before production activation. Issue #13 OPEN / PR #45 Draft Merge HOLD / no financial writes.

## 2026-10-14 4.20.33 鎖屏存活／500元 PDF 長耗時診斷 → 4.20.34

```text
Owner 4.20.33+491 (Android 10:47~10:56) observed:
    Screen-off / switch-App survival = PASS (observed; not guaranteed for every device)
    Official PDF 135200798 bytes cached, local candidate set=47
    Partial cloud-500 RESULT after 8min = NOT PROVIDED / FULL GATE HOLD
    native phase on screenshot = AMBIGUOUS, lifecycle overwritten with generic sync

4.20.34+492 current SOURCE-only code (exact head CI + Signed Canary + Owner PENDING)
    InvoiceAwardProductionPage.didChangeAppLifecycleState(resumed)
        └─ uses latest _cloudTierSummaries[_activeCloudTierCode]
             = last actually received native stage; NOT fabricated 'syncing'
        CloudAwardForegroundAcquisitionService.findMatches(onProgress)
        ├─ PLATFORM_SOURCE_SHA256 → full rehash progress / length / ETA
        ├─ PLATFORM_RENDERER_OPEN_BEGIN / WAIT → start/open duration
        ├─ PLATFORM_RENDERER_OPEN_OK → actual parsed PDF page count
        ├─ PLATFORM_RENDERER_PAGE_BEGIN → page number and candidate n/47
        └─ PLATFORM_RENDERER_CANDIDATE_SEARCH → actual pagesRead and elapsed
             (native stage only; raw PDF structural matches 0/47 ≠ confirmed non-winner)
    test/.../invoice_award_cloud_lifecycle_contract_test.dart
        └─ prevent generic status from erasing stage; assert differentiated stages

Unchanged in 4.20.34:
    PDF structure probe & SHA, Android PlatformPdfCandidateWorkerService
    PARTIAL_WAKE_LOCK 30min upper bound, separate worker pid/liveness
    true SHA full official PDF, source URL and file bytes
    candidate set and official sorted-page binary lookup/parity
    cache/LKG fail-closed, general award, manual formal-posted 500+200=700
    SQLite tables, business API, Bank direct readback = NO CHANGE

Follow-up:
    Need owner elapsed stage screenshot/terminal result to choose real optimization.
    P1 other sorted cloud tiers 800/2000/million candidate parity remains WAIT,
    no broad migration, no destructive rewrite, Issue #13 stays OPEN,
    PR #45 Draft/OPEN/Merge HOLD.
```

這一版只補實際進度的可觀測性（不是速度或完成的驗證）。實際下載／SHA、PDF 開啟與候選搜尋的瓶頸未由 Owner 截圖直接判明；不得把畫面的「更新中」當成功，不得自行把長時間等待改成完整陰性對獎。


## 2026-10-14 15:32 — Issue #13 Award Check Back-to-Top navigation (4.20.35)

```text
lib/features/invoice/invoice_award_production_page.dart
  InvoiceAwardProductionPage
    ├─ Scaffold.floatingActionButton
    │    └─ FloatingActionButton.extended Key(invoice_award_back_to_top)
    │       icon vertical_align_top, label/tooltip 「回頁首」
    │       scroll >= 560 logical pixels -> visible, top -> hidden
    ├─ SingleChildScrollView Key(invoice_award_page_scroll_view)
    │    └─ ScrollController _pageScrollController
    │         listener -> _handlePageScroll
    │         click -> _scrollToPageTop -> animateTo(0, 420ms, easeOutCubic)
    ├─ 80px bottom scroll clearance
    └─ Existing _scrollToCandidate winner-detail navigation UNCHANGED
test/invoice_award_check_route_test.dart
    └─ real widget drag -> FAB visible -> tap -> offset zero -> hidden
App / DB / Native / Source authority:
    └─ no change; no extra user data, network request, cache mutation or POSTED
```

4.20.34 had Flutter exact CI #38504361693 SUCCESS & Signed Canary #38504368496 SUCCESS but Owner Android pop/push worker UI state lost and cloud500 had >2min without measurable native stage; **Owner 4.20.34 FAIL**, full cloud500 HOLD. New 4.20.35+493 navigation is CODE-only until new exact-head tests, signed SHA/cert and Owner test; not a fix for background task reattachment. P0 next remains lifecycle route reentry/native identity/heartbeat observation before performance tuning. PR #45 stays OPEN/DRAFT/MERGE HOLD; original ledger POSTED500+200=700 frozen.

## 2026-10-14 20:11 Asia/Taipei — 4.20.35 CI exact-first-failure repair + missed hourly progression

- **Owner escalation**: no PR #45 code commit/CI progression after 15:40 failure through 20:11; an enabled hourly task does not prove execution. Monitor actual last-run + GitHub delta; if a cycle fails to perform work, record HOLD, do not claim progress.
- Failed HEAD `9c446c87abf21c815ecdb0398eba4f7d04c4e62b`: Flutter Android CI [38529830787](https://github.com/easonliu714/my_finance_app_public/actions/runs/38529830787) FAILURE at 15:44 Asia/Taipei; first red step `Run tests`, **two known deterministic failures**: `test/invoice_award_check_route_test.dart:134` empty-state 360x800 page maximum offset only 322, unable to reach intentional >560px FAB threshold; `test/p4_20_5_release_authority_test.dart:7` still expected 4.20.34+492 rather than actual 4.20.35+493. True Signed [38529838357](https://github.com/easonliu714/my_finance_app_public/actions/runs/38529838357) FAILURE because exact-head CI authority wait correctly refused; signing itself was never reached.
- Smallest repair: use 360x300 widget-test viewport for deep-scroll fixture (no fake invoice/backend/ledger entries), assert maxScrollExtent >560 then scroll/tap/hide unchanged. Align historical release-authority test to strict 4.20.35+493 and exact `issue-13-award-scroll-back-to-top-493` phase. **No production changes, no weakened assertions**, no PDF/worker/SQLite mutation. Update both canonical docs in same PR commit. New head needs new full CI and true Signed before Owner READY; old CI must never be carried forward.
- P0 still mandatory `ISSUE13_CLOUD500_NATIVE_TASK_REATTACH_AND_STAGE_PROOF`; route reentry bug from 4.20.34 owner FAIL and cloud500 latency remain HOLD. Preserve PDF source SHA, candidate universe, LKG and POSTED 500+200=700, PR Draft/Open/Merge HOLD.


## 2026-10-14 22:42 Asia/Taipei — UI/API/DB Cloud500 in-process route reattachment Gate A (4.20.36)
Architecture: InvoiceAwardProductionPage.initState -> subscribe InvoiceAwardRunningTaskBridge.shared -> restore same-period typed snapshot; disposal -> unsubscribe only; original authorization still owned by InvoiceAwardRefreshProcessGate + async refresh and native worker.
Bridge keys: one active periodId, monotonically increasing task generation lease, read-only lastStatus/scanStatus/cloudStatus/tiers/diagnostics/general candidates and winner evaluations/confirmations; any new page sees same scope and terminal snapshot without starting a duplicate fetch.
Process restart or wrong period has no trusted running authority (UNKNOWN/HOLD). Kotlin worker requestId/native PDF SHA/candidate universe SHA/PID/updatedAt evidence are not yet bridged and remain follow-up P0 Gate B; do not conflate UI reentry with authenticated native completion or PDF performance resolution.
Owner 4.20.35+493 back-to-top real device 22:38 PASS; exact Flutter CI 38562431249 SUCCESS and genuine Signed 38562441477 SUCCESS. Long-result floating 回頁首 UI CLOSED. Screenshot still reports cloud500 cached PDF awaiting parsing; full cloud500 result HOLD.
Gate A new 4.20.36+494 code + unit tests SOURCE CANDIDATE only until new exact-head CI/Signed + owner. No new API, SQLite migration, user data write, formal posting or PDF source replacement. Existing POSTED 500+200=700 untouched; PR45 DRAFT/OPEN/MERGE HOLD.



## 2026-10-14 22:56 — 4.20.36 first exact-head CI analyzer hotfix

- Candidate HEAD bd5b0db103176a04926632546d3ad3a1eeb9774e: Flutter CI [38584739463](https://github.com/easonliu714/my_finance_app_public/actions/runs/38584739463) FAIL at first step Analyze Dart code; exact log `curly_braces_in_flow_control_structures` on running_task_bridge.dart:80, 1 issue. True Signed [38584754253](https://github.com/easonliu714/my_finance_app_public/actions/runs/38584754253) fails at waiting for CI authority, signing not attempted.
- Strict smallest-safe repair: wrap BOTH generation/identity fail-closed early-return branches in explicit braces. No predicate/value/API/DB/worker change, version remains 4.20.36+494, previous CI evidence INVALID after new HEAD. Run full fresh exact-head Flutter CI and true Signed, do not blind rerun previous failed run. Gate A code only, P0 native Gate B still HOLD.


## 2026-10-20 — Gate B native-heartbeat stale UI fail-closed partial repair (CI pending)

- Existing PR #45 / `issue-13-invoice-award-official-data`; release remains `4.20.36+494` while owner-ready Gate B is HOLD. No version bump or Signed APK delivery is authorized by this partial change.
- P0 safe Dart-only scope: stale native heartbeat after 15s now maps to explicit `PLATFORM_WORKER_HEARTBEAT_STALE` status, never synthetic `PLATFORM_RENDERER_OPEN_WAIT`. PID liveness continues to be probed without implying new pages, source authority, success, or official negative evidence. Six focused Flutter tests cover fresh/boundary/stale/future timestamps.
- Native Kotlin `writeRunning` expected PDF SHA/bytes/candidate-universe SHA is NOT implemented by this change; prior platform rejection is still unresolved. `Gate B = HOLD`; 10/14 CI and Signed Canary cannot validate this new code. Require new exact-HEAD Flutter CI, subsequent native provenance completion and independently validated Signed APK before Owner Android UAT.
- Preserve approved official PDF cache/LKG and already POSTED NT$500+NT$200=NT$700. Do not change SQLite, auto-post payouts, or merge PR #45.

## 2026-10-23 15:20 — Gate B bounded-search negative authority admission (exact-head CI pending)

- Prior PR #45 HEAD `f57862bea6d8e3f67939a86a8f481fdae53aaff1` passed full Flutter Android CI #39377874799 and genuine workflow_dispatch Signed Canary #39377882262; the historical 10/20 CI-pending note is now resolved **only for that prior HEAD**.
- The 87,000-page cloud-500 sorted-PDF binary search has no complete global page-order/negative-coverage proof. A bounded-search miss is **UNKNOWN**, not a verified loss. Repository admission now rejects partial candidate matches with `CLOUD_AWARD_CANDIDATE_NEGATIVE_COVERAGE_UNPROVEN` before persistent promotion, and legacy schema-1 partial-match manifests are rejected on read. Complete all-positive candidate sets remain reusable with exact page evidence.
- This is an intentional fail-closed interim gate: partial positive matches cannot yet be promoted or reported as complete while negative coverage is unproven. Full negative evidence requires an independently proven page-order/search-completeness contract or another safe exact-match strategy. Focused repository/foreground tests were updated and extended; **new HEAD Flutter CI has not yet run**.
- No Kotlin rewrite, no reattempt of previously safety-rejected payload, no SQLite/posting/PDF/LKG mutation. Existing POSTED NT$500 + NT$200 = NT$700 remains immutable. Release stays `4.20.36+494`; Native Gate B=HOLD, PR #45 OPEN/DRAFT/MERGE HOLD, Owner-ready APK=NO.

## 2026-10-23 16:15 — Gate B future-dated native heartbeat supervision (exact-head CI pending)

- Prior PR #45 HEAD `87128cdab3edcdfef632b7b049d756dc90d29b43` passed exact-head Flutter Android CI [#39917590987](https://github.com/easonliu714/my_finance_app_public/actions/runs/39917590987): Analyze, Tests (1,929 passed), and Build debug APK. This CI belongs **only to the prior HEAD**, and is not Signed release authority.
- Dart native worker heartbeat supervision now shares one predicate for both expired and future-dated timestamps, including the running-result and result-absent liveness probes. A future native timestamp cannot suppress a liveness probe or be displayed as fresh callback progress. Invalid native clock stages display `PLATFORM_WORKER_HEARTBEAT_STALE` and no ETA; PID alive is never reinterpreted as fresh progress.
- Four focused pure-Dart regression tests cover fresh, exact 15-second boundary, expired and future-dated ages. This is not an Android end-to-end or Native Gate B proof; new exact-head Flutter CI remains pending until independently observed.
- No Kotlin payload reattempt, no Native terminal provenance/atomic publication proof, no official PDF/LKG/SQLite/accounting change. Preserve POSTED NT$700, release `4.20.36+494`, PR OPEN/DRAFT/MERGE HOLD, and Owner-ready APK=NO.

## 2026-10-23 18:15 — Gate B native COMPLETE terminal metadata fail-closed (new exact-head CI pending)

- Prior PR #45 HEAD `ef281cae02470faeee28ae5ff532edc9c1f16f78` passed exact-head Flutter Android CI [#39923453125](https://github.com/easonliu714/my_finance_app_public/actions/runs/39923453125), 1,933 tests, Analyzer and debug build. Genuine `workflow_dispatch` Signed Canary [#39923463616](https://github.com/easonliu714/my_finance_app_public/actions/runs/39923463616) completed SUCCESS and published artifact 12489154321; independent APK inspection for that artifact is NOT claimed. These are **prior HEAD** authorities only.
- Dart crash-isolated platform PDF worker now rejects `complete` Terminal when engine, exact completion stage, positive PID, prior PID continuity, or native terminal timestamp (future / earlier than last heartbeat / missing) fails. Nine focused pure-Dart tests cover positive and negative envelope cases. Existing requestId, source PDF SHA/bytes, candidate-universe SHA and page evidence checks remain unchanged.
- This is an additive Dart-only fail-closed metadata gate; it does NOT prove Native atomic publication, Failed Terminal custody, PDF global page-order completeness, or Android real-device behavior. Previously safety-rejected Kotlin payload was NOT retried. Native Gate B=HOLD; new exact-head Flutter CI pending; no Owner-ready APK.
- Keep `4.20.36+494` until native proof, signed exact-head release and Owner Android UAT. Preserve official PDF/LKG, SQLite and already POSTED NT$500+NT$200=NT$700. PR #45 remains OPEN/DRAFT/MERGE HOLD; no direct main write.

## 2026-10-23 19:15 — Gate B FAILED terminal envelope validation (new exact-head CI pending)

- Prior PR #45 HEAD `b36e5d88ef04a44f4e68055207acc67ab807e9f8` passed exact-head Flutter Android CI [#39938393825](https://github.com/easonliu714/my_finance_app_public/actions/runs/39938393825): Analyzer, 1,942 Flutter tests and debug APK build. Genuine `workflow_dispatch` Signed Canary [#39938403843](https://github.com/easonliu714/my_finance_app_public/actions/runs/39938403843) completed SUCCESS, artifact 12496421531; independent APK byte-level inspection is NOT claimed. These successes apply **only to prior HEAD**.
- Dart crash-isolated worker now fail-closes the currently emitted native `failed` envelope: exact status, Platform engine, positive nonfuture terminal timestamp (and monotonic against a previously observed native heartbeat), plus bounded native error-code grammar. Early failures without a native heartbeat do not falsely require a post-start heartbeat timestamp. Ten focused tests cover positive/negative cases.
- Kotlin's existing failed payload has no PID, stage, PDF SHA/bytes or candidate-universe SHA; this Dart-only validation does **not** supply missing native evidence, retain failed result files or prove atomic terminal publication. Native Gate B remains HOLD. Previously safety-rejected Kotlin payload was NOT retried.
- No version bump; `4.20.36+494` stays current. No Owner-ready APK. Preserve official 135200798-byte PDF/LKG, SQLite and already POSTED NT$500+NT$200=NT$700; PR #45 remains OPEN/DRAFT/MERGE HOLD; no main writes. New exact-head CI/Signed remain pending.

## 2026-10-23 19:21 — Immediate repair of first failed exact-head Analyzer Gate

- Commit `fc023b17af3f39777b41e75eee1cbfae9e104e4b` triggered exact-head Flutter Android CI [#39945369210](https://github.com/easonliu714/my_finance_app_public/actions/runs/39945369210) FAIL in the **first failing step `Analyze Dart code`** (job 120386613538), before tests/build. The malformed Dart source at line 201 was caused by source-string replacement expansion of the literal `$'` sequence, which duplicated a file suffix and left an unterminated raw RegExp. CI logged 29 analyzer issues including duplicate declarations; the test fixture also used unsupported string multiplication.
- Rebuild the Dart source from immutable parent `b36e5d88ef04a44f4e68055207acc67ab807e9f8` using literal-safe callback replacement; enforce exactly one crash-isolated lookup and one cancellation class, restore a valid bounded FAILED error-code RegExp, and replace test string multiplication with `List<String>.filled(...).join()`. These are minimal corrections to the preceding FAILED envelope gate; no Kotlin or accounting changes.
- New exact-head Flutter CI is **PENDING**. Do not inherit the previous HEAD's CI/Signed results, do not rerun old HEAD, and do not release APK. Native Gate B=HOLD; PR #45 OPEN/DRAFT/MERGE HOLD, `4.20.36+494`, POSTED NT$700, official PDF/LKG and SQLite preserved.


## 2026-10-23 21:00 Asia/Taipei — Dart Running envelope identity continuity (new CI pending)

- Verified previous PR #45 exact HEAD `c6f7824ef617483bc90621d5c26a8b39300c7665`: Flutter Android CI [39951954395](https://github.com/easonliu714/my_finance_app_public/actions/runs/39951954395) SUCCESS; genuine workflow_dispatch Signed Canary [39951967243](https://github.com/easonliu714/my_finance_app_public/actions/runs/39951967243) SUCCESS, artifact 12502515970. Historical success belongs to that HEAD only. Neither grants Owner-ready status.
- New Dart-only scope validates fields actually emitted by Kotlin `writeRunning` before reporting any native `running` progress: positive/unchanged Worker PID, exact candidate_count, candidate_index bounds, exact source_bytes_total and bounded bytes_read, engine/status envelope, native timestamp nonfuture and monotonic after an earlier heartbeat. 11 regression cases are added using a representative currently emitted Running envelope, without changing the native worker contract.
- Does NOT claim full PDF SHA/candidate-universe SHA identity in each Running heartbeat, proven global negative coverage, source File custody, actual Android testing, or Native Gate B closure. Prior Kotlin `create_blob` safety refusal was not retried; native `writeRunning` still lacks expected SHA fields. Current release remains `4.20.36+494`; this new HEAD needs its own complete Flutter CI/Signed and remains `HOLD_NOT_READY_FOR_OWNER_DEVICE`.
- No SQLite, accounting posting, official PDF re-download, cache/LKG, or main mutations. Keep PR #45 OPEN/DRAFT/MERGE HOLD and previously POSTED NT$500+NT$200=NT$700 frozen.


## 2026-10-23 21:30 Asia/Taipei — Native Running stage/page evidence fail-closed (new exact-head CI pending)

- Prior immutable PR #45 HEAD `b0c19ad8054ddf07818c993fe82fca89dc19379c` passed exact-head Flutter Android CI [39957816292](https://github.com/easonliu714/my_finance_app_public/actions/runs/39957816292): Analyzer, 1,963 Flutter tests, debug build. Genuine workflow_dispatch Signed Canary [39957826898](https://github.com/easonliu714/my_finance_app_public/actions/runs/39957826898) completed both jobs SUCCESS, artifact 12504338016; its APK has NOT been independently inspected or accepted for Owner device. These are PRIOR-HEAD facts only.
- New Dart-only fail-closed gate constrains Running stage to the six exact values emitted by unchanged Kotlin `writeRunning`, and requires typed nonnegative page number/count/read count and stage elapsed time, pagesRead <= pageCount, source SHA stage with zero renderer progress, full source-byte count before renderer open/search, OPEN_OK with positive page count, and candidate/page evidence during page search. This prevents fabricated page counts, fake search progress or terminal-like Running stage from becoming visible native progress. Seven focused tests cover all six legitimate stage shapes and malformed envelopes.
- This does NOT prove native PDF SHA/candidate-universe SHA in Running, requestId/PID lifecycle beyond existing guards, native atomic terminal publication, Failed Terminal evidence custody, or global sorted-PDF negative coverage. The Oct15 safety-rejected Kotlin payload was NOT retried; Kotlin blob 5cc553afa84cd6d10d6a0170ce8c0ad14a993cb8 remains unchanged. Gate B=HOLD; release stays `4.20.36+494`, no Owner-ready APK.
- No main/SQLite/accounting/official PDF/LKG mutation, no automatic posting; existing POSTED NT$500+NT$200=NT$700 remains frozen. PR #45 stays OPEN/DRAFT/MERGE HOLD. New commit must pass fresh exact-head Flutter CI and genuine Signed before any release consideration.

## 2026-10-23 22:14 Asia/Taipei — Native terminal evidence cleanup fail-closed (exact-head CI pending)

- Prewrite authority: PR #45 OPEN/DRAFT, HEAD `d856c1b80250e083724c0d2ef5c9858bd9656fff`; Flutter Android CI #39961962106 SUCCESS (prior exact HEAD). Existing governance documents read from that same HEAD. New Dart-only source change retains native FAILED, invalid COMPLETE, and incomplete/negative-search result JSON rather than deleting it in a `finally` block. Only a fully validated COMPLETE with every candidate positively matched may be removed after read.
- New file `test/features/invoice/invoice_award_native_terminal_evidence_cleanup_test.dart` adds six focused temporary-file tests for all-positive cleanup, FAILED preservation, invalid COMPLETE preservation, partial/unknown preservation, empty/missing status preservation, and absent-file idempotence. This is real file IO exercised in Flutter tests; no Android device proof is claimed before CI.
- Scope limit: retention is in the existing native-provided result path and is not guaranteed durable/atomic, bounded, or secure by this Dart-only change. Kotlin Running source SHA/candidate SHA, native failed PID/stage custody, globally sorted 87K-page PDF negative proof, terminal atomicity and lifecycle cleanup remain Native Gate B HOLD. Prior safety-blocked Kotlin payload was not retried or worked around.
- PR stays OPEN/DRAFT/MERGE HOLD. Release `4.20.36+494` unchanged. Official PDF 135200798 bytes/LKG, SQLite, main, and already POSTED NT$500+NT$200=NT$700 unchanged. New commit requires fresh exact-head Flutter CI and Signed; no Owner-ready APK.

## 2026-10-23 23:15 Asia/Taipei — Native COMPLETE numeric evidence strict-type gate (new exact-head CI pending)

- Prewrite live PR #45 OPEN/DRAFT HEAD `5d6471980f8b81439db4f73036ecab79f7abfaef`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`. That prior HEAD passed Flutter Android CI [39968248589](https://github.com/easonliu714/my_finance_app_public/actions/runs/39968248589): analyzer, 1,976 Flutter tests and debug build. True exact-head workflow_dispatch Signed Canary [39968265090](https://github.com/easonliu714/my_finance_app_public/actions/runs/39968265090) completed both jobs SUCCESS and produced artifact 12510205829. Signed APK bytes have NOT been independently inspected and are not Owner-ready.
- Independent Dart-only change: `cloudAwardNativeCompleteNumericEvidenceViolation` now rejects fractional, string, boolean or absent JSON `page_count`, `pages_read`, `candidate_count`, `source_bytes`, and noninteger `matched_pages` values before any `num.toInt()` truncation in the actual COMPLETE consumer. Eight focused tests cover positive integer envelopes and malformed evidence. Preserve existing COMPLETE provenance checks and all-positive/unknown-negative fail-closed policy.
- This is strict evidence shape, NOT native PDF SHA/candidate SHA running custody, global 87K-page negative coverage, native atomic terminal publication, durable failed evidence or Android device validation. No Kotlin write; the previously safety-blocked Kotlin payload was NOT retried. `NATIVE_GATE_B=HOLD`, `OWNER_READY_APK=NO`; new HEAD Flutter CI/Signed are separately pending.
- Release stays `4.20.36+494`; PR remains OPEN/DRAFT/MERGE HOLD. No official PDF/LKG, SQLite, main, payout, or already POSTED NT$500+NT$200=NT$700 changes.

## 2026-10-24 00:18 Asia/Taipei — Native COMPLETE exact-match identity gate (new exact-head CI pending)

- Fresh prewrite: PR #45 OPEN/DRAFT HEAD `3142c0af03d81e054449e09357927bfd62867378`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`; Flutter Android CI [39976628262](https://github.com/easonliu714/my_finance_app_public/actions/runs/39976628262) SUCCESS (analyzer, 1,984 tests, Android debug build). Genuine same-head Signed workflow_dispatch [39976640421](https://github.com/easonliu714/my_finance_app_public/actions/runs/39976640421) SUCCESS, artifact 12512862587; APK bytes NOT independently inspected and NOT Owner-ready.
- Independent Dart repair: `cloudAwardNativeCompleteMatchedIdentityViolation` rejects malformed, duplicate, non-string, unnormalized, out-of-universe COMPLETE matches and inconsistent `matched_pages` keys before lossy normalization. Nine focused tests added in `test/features/invoice/invoice_award_native_complete_match_identity_test.dart`. Preserve PDF SHA/bytes/candidate SHA checks and all-positive-only persistence/cleanup; empty or partial matches remain UNKNOWN, not proven negatives.
- Scope remains PARTIAL: Kotlin Running PDF SHA/candidate SHA, global 87K-page negative proof, durable failed-terminal custody and native atomicity, Android device proof remain unresolved. Oct15 safety-blocked Kotlin payload not retried or evaded. `NATIVE_WRITE_SAFETY_HOLD`, `NATIVE_GATE_B=HOLD`, `OWNER_READY_APK=NO`.
- PR OPEN/DRAFT/MERGE HOLD, version `4.20.36+494` unchanged; official PDF/LKG/SQLite, already POSTED NT$700 and main untouched. New HEAD needs its own exact-head Flutter CI and genuine Signed before release consideration.

## 2026-10-24 01:15 Asia/Taipei — PR45 first-failure structural recovery (exact-head CI pending)

- Fresh prewrite PR #45 OPEN/DRAFT HEAD `c2592462bc31cc47aaa754866a0848d6f17e2d0a`; main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`; Issue #13 OPEN; version `4.20.36+494`. Flutter Android CI [39986130472](https://github.com/easonliu714/my_finance_app_public/actions/runs/39986130472) FAILED at first job `120525681128`, step `Analyze Dart code`: `invoice_award_cloud_candidate_scope.dart:322:35` unterminated string; subsequent diagnostics cascade. Signed workflow_dispatch [39986140954](https://github.com/easonliu714/my_finance_app_public/actions/runs/39986140954) FAILED at exact-head Flutter authority wait; no Signed APK artifact.
- Repair is rebuilt from the **complete 980-line verified parent Dart blob** `7a104e652bfd6518803bf586deeaea57da3cfea4` (commit `3142c0af03d81e054449e09357927bfd62867378`), not from the corrupted 1694-line source. Insert exactly one closed `cloudAwardNativeCompleteMatchedIdentityViolation` helper, and invoke it in actual COMPLETE consumer **before** lossy `normalizeCloudCandidateNumbers`. Keep nine existing focused tests and add one source-wiring regression test; preflight rejects duplicate declarations/source tail. Preserve provenance, terminal, numeric, partial/empty UNKNOWN and all-positive-only cleanup gates.
- No Kotlin modification or retry of the Oct15 safety-blocked payload. `NATIVE_WRITE_SAFETY_HOLD` and `NATIVE_GATE_B=HOLD`: Kotlin Running identity, global 87K-page negative proof, atomic terminal and durable evidence remain incomplete. `OWNER_READY_APK=NO`; do not bump version, post transactions, change official PDF/LKG/SQLite, touch main or merge PR. New exact-head analyzer/full Flutter tests/debug build and authentic Signed must be independently verified.


## PR45 Native COMPLETE positive-page read custody — 2026-10-24 02:15 Asia/Taipei

- Prewrite exact PR HEAD `5edf28278a323996e32f62ec5357b0d5b63bceb4` (OPEN/DRAFT, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`); Flutter Android CI [39993726508](https://github.com/easonliu714/my_finance_app_public/actions/runs/39993726508) SUCCESS, 1,994 tests, Analyze/Debug build PASS. Genuine workflow_dispatch Signed [39993736507](https://github.com/easonliu714/my_finance_app_public/actions/runs/39993736507) BuildInspect SUCCESS, artifact 12520203151; this is 4.20.36+494 and NOT owner-ready.
- Real defect: COMPLETE accepted positive `matched_pages` despite `pages_read=0`. Add fail-closed page-evidence guard before returning normalized matches, plus two focused regression tests; preserve zero-read/zero-match UNKNOWN and existing all-positive-only promotion. **This new commit has no inherited CI or Signed approval**; exact-head verification pending.
- Native Running PDF SHA/bytes/candidate SHA chain, global sorted-PDF negative coverage, durable terminal atomicity and Android device Gate B remain HOLD. `NATIVE_WRITE_SAFETY_HOLD` for previously blocked Kotlin payload; no retry/evasion. PR Draft/Merge HOLD, main, POSTED NT$700, 135200798-byte official PDF/LKG, SQLite unchanged. No release bump; owner APK NOT_READY.


## PR45 Native COMPLETE distinct-pages upper-bound guard — 2026-10-24 Asia/Taipei

- Fresh prewrite authority: PR #45 OPEN/DRAFT, expected parent HEAD `41de260fd487699df05274546634d8c04e7fce2b`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`; exact-parent Flutter Android CI [40001986111](https://github.com/easonliu714/my_finance_app_public/actions/runs/40001986111) SUCCESS (Analyze, 1,996 tests, debug build); genuine Signed workflow_dispatch [40001998726](https://github.com/easonliu714/my_finance_app_public/actions/runs/40001998726) Validate/BuildInspect SUCCESS, artifact `12524022943` (not Owner-ready).
- Native Kotlin `pagesRead` is the cardinality of successfully read distinct pages, so `pages_read > page_count` is impossible. Add minimal Dart COMPLETE numeric-evidence fail-closed check before terminal acceptance, with focused overrun and valid-boundary/sparse-binary-search tests. A high `matched_pages` page index **must not** be compared to `pages_read`. Existing zero-read positive rejection and zero-read/zero-match UNKNOWN remain unchanged. New commit requires its own exact-head CI and Signed validation; parent success cannot be inherited.
- `NATIVE_GATE_B=HOLD`, `NATIVE_WRITE_SAFETY_HOLD`, `OWNER_READY_APK=NO`, PR Draft/Merge HOLD. Native Running source/candidate SHA chain, 87K-page negative coverage, terminal atomicity and durable custody remain unproven; no Kotlin safety-blocked payload retry, version bump, ledger posting, PDF/LKG/SQLite/main modification.


## PR45 Native COMPLETE matched-page distinct-read custody — 2026-10-24 Asia/Taipei

- Fresh prewrite authority: PR #45 OPEN/DRAFT exact parent `5e0f7bb3d9332b45df7975bd75651eed6fce0ff7`; main remains `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`. Parent Flutter Android CI [40009941287](https://github.com/easonliu714/my_finance_app_public/actions/runs/40009941287) SUCCESS (Analyze, 1,998 tests, debug APK). Genuine workflow_dispatch Signed [40009957536](https://github.com/easonliu714/my_finance_app_public/actions/runs/40009957536) Validate/BuildInspect SUCCESS, artifact `12527292259`, not owner-ready.
- Native Kotlin `pageTokens` adds successfully read page numbers to `pagesRead` and assigns `matchedPages` only from those page tokens. The COMPLETE envelope must satisfy `matched_pages.values.toSet().length <= pages_read`. Add Dart fail-closed guard before consumer accepts COMPLETE, and three focused tests for impossible distinct-page overrun, legitimate shared page, and sparse high page index. Do **not** compare a matched page index to `pages_read`; zero-read/empty-match remains UNKNOWN, not proven negative. New exact-head Flutter CI and genuine Signed evidence are required and **not inherited** from the parent.
- Native source/candidate identity, globally complete 87K-page negative proof, atomic terminal publication, durable evidence and Android device Gate B remain HOLD. Previously blocked Kotlin create_blob is not retried or bypassed. PR OPEN/DRAFT/MERGE HOLD, no version bump, auto-post, official PDF/LKG/SQLite, POSTED NT$700 or main changes. `OWNER_READY_APK=NO`.


## PR45 Native malformed-result liveness supervision — 2026-10-24 Asia/Taipei

- Fresh prewrite authority: PR #45 OPEN/DRAFT parent `39f5fb51c8a93c4fe0a48f11e975f9216dcdbcaf`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`. Parent exact-head Flutter Android CI [40017501646](https://github.com/easonliu714/my_finance_app_public/actions/runs/40017501646) SUCCESS (Analyze, 2,001 tests, debug APK). Genuine workflow_dispatch Signed [40017511721](https://github.com/easonliu714/my_finance_app_public/actions/runs/40017511721) Validate/BuildInspect SUCCESS; artifact `12531295441` is not independently reverified and not Owner-ready.
- Confirmed Dart defect: when native result exists but JSON cannot be decoded, a 50ms retry bypasses the existing PID-bound stale heartbeat liveness probe. Kotlin writeAtomic() rename-failure fallback writes the target non-atomically, allowing persistent partial JSON after worker death. This commit shares one throttled OS PID probe across malformed, running and absent-result paths. A malformed result with previously verified PID and stale heartbeat now probes OS liveness; dead PID fails closed as PROCESS_DIED, alive PID retries without accepting malformed terminal or negative coverage. No verified PID means no guessed process death. Malformed stale notices reuse last observed native progress values with truthful PLATFORM_WORKER_HEARTBEAT_STALE and no ETA.
- Add three real temp-file plus mocked MethodChannel integration regressions for partial JSON after observed Running PID (dead/alive) and malformed JSON without trusted PID; test-only seam retains approved sorted-source gate. Dart-only: no Kotlin changes or blocked payload retry. New HEAD Flutter full CI and genuine Signed must be verified independently.
- Native Gate B HOLD: Running source PDF/candidate SHA chain, 87K-page global negative proof, terminal atomic publication, durable custody, owner Android UAT. Zero/partial matches remain UNKNOWN. No version bump, auto-post, official PDF/LKG/SQLite, POSTED NT$700, main or PR merge changes. `OWNER_READY_APK=NO`.


## PR45 malformed-result liveness first-CI analyzer repair — 2026-10-24 Asia/Taipei

- Initial native malformed-result liveness commit `76a66758590d61c992f7af1005ce70ff4868b2e5` published/read back with source, three real temp-file/MethodChannel integration tests and both canonical docs. Exact-head Flutter Android CI [40025735014](https://github.com/easonliu714/my_finance_app_public/actions/runs/40025735014) FAILED at first failing job `120661331375`, step `Analyze Dart code`: `unnecessary_non_null_assertion` at `invoice_award_cloud_candidate_scope.dart:785:48`; tests/debug build SKIPPED. Raw log confirms sole analyzer warning, not a test or native failure.
- Minimal follow-up: remove only the redundant `!` from `final previous = lastNativeProgress!` after the prior null check; Dart flow promotion already establishes non-null. No assertion relaxation, no behavior change, no Kotlin changes. Retain all integration tests, throttled OS PID liveness, truthful STALE, malformed JSON retry and UNKNOWN negative authority. New exact-head Flutter CI/full tests/debug APK and genuine Signed must be independently verified; parent failures/successes cannot be inherited.
- PR OPEN/DRAFT/MERGE HOLD, version `4.20.36+494`, Native Gate B / native write safety HOLD, no Owner-ready APK, no main/PDF/LKG/SQLite/POSTED NT$700 modifications.


## PR45 native OS-liveness reply identity guard — 2026-10-24 Asia/Taipei

- Fresh parent `f5d2f40346059fd3e0046c4a716e994d3eee3d41`: PR #45 OPEN/DRAFT, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`; exact-head Flutter Android CI [40025993280](https://github.com/easonliu714/my_finance_app_public/actions/runs/40025993280) SUCCESS (Analyzer, 2,004 tests, debug build), genuine workflow_dispatch Signed [40026002011](https://github.com/easonliu714/my_finance_app_public/actions/runs/40026002011) SUCCESS, artifact `12534056875` (not owner-ready; no independent ZIP/APK byte validation).
- Exact Kotlin `PdfTextPlugin.getPlatformCandidateWorkerLiveness` returns `alive` bool, `pid` int, expected `:platform_candidate_worker` processName and `exitReasonCode` int; Dart previously classified null/missing/non-bool `alive` as verified `PROCESS_DIED`, ignored reply PID/process identity and truncated exit code via `num.toInt()`. New Dart-only `cloudAwardNativeLivenessEnvelopeViolation` rejects unknown response shape, mismatched PID and process name before any death classification; only explicit `alive=false` with valid envelope yields PROCESS_DIED. No fabricated progress or negative search authority. This is not PID-reuse immunity.
- Existing 3 real temp-file + mocked MethodChannel liveness tests retained; 5 new integration negatives exercise null/missing/string alive, wrong PID and wrong processName on stale verified-PID + malformed-result path. New HEAD Flutter full CI and genuine Signed require independent verification; no Kotlin change or blocked-payload retry.
- Native Gate B remains HOLD: Running source/candidate SHA chain, 87K-page global negative proof, terminal atomic publication and durable custody, PID-reuse proof, Owner Android UAT. Zero/partial matches UNKNOWN; no release bump, ledger auto-post, PDF/LKG/SQLite, POSTED NT$700, main or merge changes. `OWNER_READY_APK=NO`.


## PR45 Native OS liveness UNKNOWN-vs-DEAD evidence guard — 2026-10-24 Asia/Taipei

- Fresh prewrite PR #45 OPEN/DRAFT parent `f84bc06932b59729c1ead5ef3aeeb52f4b30ff70`; main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`; pubspec `4.20.36+494`. Parent exact-head Flutter Android CI [40033200629](https://github.com/easonliu714/my_finance_app_public/actions/runs/40033200629) SUCCESS (Analyzer, 2,009 tests, debug APK). Genuine exact-head workflow_dispatch Signed [40033209705](https://github.com/easonliu714/my_finance_app_public/actions/runs/40033209705) Validate/BuildInspect SUCCESS, artifact `12537635802` (not independently ZIP/APK reverified; not Owner-ready).
- Confirmed native Kotlin `getPlatformCandidateWorkerLiveness`: missing `runningAppProcesses` PID yields `alive=false` even when `getHistoricalProcessExitReasons` has no matching record (`exitReasonCode=-1`), or returns Android `REASON_UNKNOWN=0`. Dart previously mislabelled both as verified PROCESS_DIED. Minimal Dart envelope fail-closed now returns `CLOUD_AWARD_CANDIDATE_WORKER_LIVENESS_UNVERIFIED` for `alive=false` and exit reason <=0; rejects inconsistent `alive=true` with non-(-1) historical reason. Existing `alive=false` reason 9 PROCESS_DIED and `alive=true` reason -1 retry remain intact. Add three real malformed temp-result + observed Running PID + MethodChannel integrated regressions. No source/candidate/terminal authority or negative coverage promoted; new HEAD CI and Signed are PENDING until independently observed.
- `NATIVE_GATE_B=HOLD`, `NATIVE_WRITE_SAFETY_HOLD`, `OWNER_READY_APK=NO`; Kotlin Running source/candidate SHA chain, 87K-page global negative coverage, atomic terminal/durable custody and PID reuse proof remain unresolved. No blocked Kotlin payload retry, release bump, auto-post, official PDF/LKG/SQLite, POSTED NT$700, main or merge change.


### 2026-10-24 Gate B — Native SEARCH pages-read monotonicity (Dart-only, CI pending)

- Parent exact HEAD `c642c66959b03b3921192ee2572693c018117882` OPEN/DRAFT; main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`; version `4.20.36+494`. Parent Flutter Android CI #40038352820 SUCCESS (Analyze, 2012 tests, Debug APK), genuine workflow_dispatch Signed #40038361565 Validate/BuildInspect SUCCESS, artifact 12539615333; no independent APK ZIP CRC/signer verification, not Owner-ready.
- Confirmed Kotlin `pagesRead` is a request-local linked set updated only on newly read pages; SEARCH Running snapshots for the same verified request/PID must never regress. New Dart guard compares only previously validated `PLATFORM_RENDERER_CANDIDATE_SEARCH` page-read cardinality; OPEN_WAIT/OPEN_OK concurrency remains outside this comparison. Rejects regressed 13→12, allows 13→13 and 13→14, with real result-file + MethodChannel consumer regression. Production caller validates before emitting progress; no synthetic COMPLETE or negative evidence.
- Only Dart source, focused unit/integration tests, and the two existing canonical docs change. New exact-head CI/Signed require independent verification after publication. `NATIVE_GATE_B=HOLD`, `NATIVE_WRITE_SAFETY_HOLD`, `OWNER_READY_APK=NO`. Kotlin Running source/candidate SHA chain, global negative proof, atomic terminal custody, PID reuse remain unresolved. No release bump, Kotlin write, official PDF/LKG/SQLite/POSTED NT$700, main write or merge.

## 2026-10-24 10:15 Asia/Taipei — PR45 SEARCH candidate-index monotonicity (code publication)
- Source-bound Kotlin `candidates.forEachIndexed` is sequential; verified `PLATFORM_RENDERER_CANDIDATE_SEARCH` Running snapshots for the same request/PID cannot decrease `candidate_index`. New Dart guard fails closed on 2→1, accepts 2→2/3, and excludes concurrent `OPEN_WAIT`/`OPEN_OK` from this comparison.
- Changes: production `cloudAwardNativeRunningEnvelopeViolation` and `_findMatchesCrashIsolated`; 3 focused unit tests and 1 real temporary-result-file/MethodChannel consumer integration test. No Kotlin changes. Publish only to existing PR45 Draft branch; new exact-head CI and genuine Signed workflow_dispatch must be read back independently after publication.
- Prior exact-head 09f058dc CI #40048944237 SUCCESS (2016 tests, Analyze and Debug build PASS), genuine Signed #40048950040 Validate/BuildInspect SUCCESS, artifact 12543212022; those results do not transfer to this commit.
- `NATIVE_GATE_B=HOLD`, `NATIVE_WRITE_SAFETY_HOLD`, `OWNER_READY_APK=NO`: native Running source/candidate SHA chain, globally complete negative proof, terminal atomicity/durable custody and PID reuse unresolved. Version remains 4.20.36+494; no official PDF/LKG/SQLite/posted NT$700/main/merge changes.

## 2026-10-24 11:15 Asia/Taipei — PR45 SEARCH page-count continuity (code publication)
- Source-bound immutable Kotlin blob 5cc553afa84cd6d10d6a0170ce8c0ad14a993cb8 obtains one `renderer.pageCount` after opening the PdfRenderer. For one request/PID, verified SEARCH Running snapshots must have identical `page_count`; 87000→87001 fails closed with `CLOUD_AWARD_CANDIDATE_WORKER_RUNNING_PAGE_COUNT_CHANGED`. Equal counts remain valid, and concurrent OPEN_WAIT/OPEN_OK do not establish or challenge SEARCH page-count authority.
- Production `cloudAwardNativeRunningEnvelopeViolation` and `_findMatchesCrashIsolated` now preserve last verified SEARCH page count, validate before progress callbacks, and do not infer dense page reads. Three focused unit tests plus one real temporary-result-file/MethodChannel consumer integration regression added. No Kotlin write or release bump.
- Live prewrite PR HEAD 4549f774cda2a4f781e750990bf919e06de87ca6 OPEN/DRAFT, main a8f1ad67671b93d9bbe52d5cf7599e2f308474b8; Flutter CI #40053494049 Analyze, 2020 tests and Debug build SUCCESS. Signed bridge #40053493923 SUCCESS, but actual same-HEAD workflow_dispatch BuildInspect/artifact NOT_VERIFIED and cannot be inherited. New commit requires independent exact-head CI/Signed readback.
- `NATIVE_GATE_B=HOLD`, `NATIVE_WRITE_SAFETY_HOLD`, `OWNER_READY_APK=NO`. Running PDF/candidate SHA identity, global negative coverage, terminal atomicity/durable custody and PID reuse unresolved. Official PDF/LKG/SQLite/POSTED NT$700/main/merge untouched; version 4.20.36+494.


## 2026-10-24 PR #45 Native SEARCH page identity continuity — CI pending
- Fresh prewrite authority: PR OPEN/DRAFT, parent `b37cdbedd79ca2df146d1f5948c29adf994012f1`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, pubspec `4.20.36+494`. Parent Flutter Android CI [40057653100](https://github.com/easonliu714/my_finance_app_public/actions/runs/40057653100) SUCCESS (Analyze, 2,024 tests, debug APK); genuine parent workflow_dispatch Signed [40057657752](https://github.com/easonliu714/my_finance_app_public/actions/runs/40057657752) Validate/BuildInspect SUCCESS, artifact `12546418882` (not independently ZIP CRC/APK verified; not Owner-ready).
- Kotlin immutable `pageTokens()` skips cached pages and emits SEARCH only after `pagesRead.add(pageNumber)`; a verified same-request/PID SEARCH snapshot cannot change `page_number` with unchanged `pages_read`, nor increase `pages_read` while repeating the same `page_number`. Dart `cloudAwardNativeRunningEnvelopeViolation` now checks the adjacent verified SEARCH tuple, and the actual result-file consumer preserves the prior SEARCH page number. OPEN_WAIT/OPEN_OK concurrent heartbeat stages remain exempt; sparse binary-search page numbers remain valid.
- Added four focused unit regressions plus one real temporary JSON/MethodChannel consumer integration regression. New HEAD Analyze/full tests/debug APK and true Signed are PENDING until independently observed. No Kotlin edit; no negative-search authority or native source/candidate SHA chain promoted.
- `NATIVE_GATE_B=HOLD`; `NATIVE_WRITE_SAFETY_HOLD`; `HOLD_NOT_READY_FOR_OWNER_DEVICE`; PR Draft/Merge HOLD; no release version bump, ledger posting, PDF/LKG/SQLite changes, or direct main write.

## 2026-10-24 PR #45 verified Running source-byte continuity — CI pending
- Exact parent `e73264276e0e257ce3a6d6497f9d2a51813c7b6e` (OPEN/DRAFT, main unchanged), Flutter Android CI 40061927213 Analyze/2,029 tests/debug APK PASS; true workflow_dispatch Signed 40061933108 Validate/BuildInspect PASS with artifact 12548890545. This parent artifact is NOT independently CRC/APK-signature verified or Owner-ready.
- Current Kotlin `sha256File` increments `totalRead` and emits source hash Running progress; all later renderer Running stages report the complete source byte length. Dart `cloudAwardNativeRunningEnvelopeViolation` now rejects lower `source_bytes_read` than the prior validated Running observation for the same request/PID. Consumer records only verified source-byte evidence before emitting UI progress. OPEN_WAIT/OPEN_OK concurrent stages at full bytes remain accepted; malformed JSON retry/liveness, SEARCH page identity and zero/partial UNKNOWN semantics are unchanged.
- Added four focused unit regressions and one actual temporary result-file/MethodChannel consumer integration regression. This is source-byte *continuity*, NOT native PDF SHA/candidate-universe SHA Running identity proof; exact new HEAD Flutter Analyze/full tests/debug build and true Signed remain pending independent readback.
- `NATIVE_GATE_B=HOLD`; `NATIVE_WRITE_SAFETY_HOLD` (previous blocked Kotlin payload not retried); global negative coverage, atomic terminal/durable custody and PID-reuse provenance unresolved. Version 4.20.36+494, PR Draft/Merge HOLD, official PDF/LKG/SQLite/POSTED NT$700/main unchanged; `HOLD_NOT_READY_FOR_OWNER_DEVICE`.

## 2026-10-25 PR #45 verified SEARCH-to-opening Running stage regression — code publication, CI pending
- Fresh prewrite authority: PR #45 OPEN/DRAFT, parent `7107be653a7c618e9c6004e3362f7f8629a8c749`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, pubspec `4.20.36+494`. Parent Flutter CI #40073566843 Analyze/2,034 tests/debug APK PASS; genuine parent workflow_dispatch Signed #40073572126 Validate/BuildInspect PASS, artifact 12552893101 (independent ZIP CRC/APK signer verification absent). These parent results do not transfer to a new commit.
- Kotlin immutable native openHeartbeat can finish an OPEN_WAIT write after the main worker has entered SEARCH because interrupt() has no join or result-writer mutex. Dart Running consumer now rejects SOURCE_SHA256/OPEN_BEGIN/OPEN_WAIT/OPEN_OK after verified same-request/PID SEARCH evidence, before UI progress; PAGE_BEGIN/SEARCH iteration and opening stages before SEARCH remain legal. Four obsolete positive unit expectations changed to fail-closed, two focused positive/negative unit tests added, and one actual temporary result-file/MethodChannel integration regression added.
- This guard does NOT fix native same-request result-writer race, stale RUNNING overwriting COMPLETE, fixed .tmp collision, rename-failure non-atomic fallback, PDF/candidate SHA Running identity, source FD binding, PID-reuse custody, or global negative coverage. Zero/partial miss remains UNKNOWN. `NATIVE_GATE_B=HOLD`, `NATIVE_WRITE_SAFETY_HOLD`, `NATIVE_RESULT_WRITER_RACE_HOLD`, `HOLD_NOT_READY_FOR_OWNER_DEVICE`; PR Draft/Merge HOLD. Exact new HEAD Flutter CI and genuine Signed must be independently read back before claiming PASS. Official PDF/LKG/SQLite/POSTED NT$700/main unchanged; no release version bump.

## 2026-10-25 PR #45 PAGE_BEGIN verified-SEARCH continuity — source-bound Dart patch (new HEAD CI/Signed pending)
- Prewrite exact authority: PR OPEN/DRAFT parent `d937019fd638872e2f48468336def70b274cf141`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`; parent Flutter CI #40110641628 Analyze/2,037 tests/debug APK PASS and genuine workflow_dispatch Signed #40110648058 Validate/BuildInspect PASS, artifact 12567881290. Parent checks must not be inherited by this change.
- Kotlin `pageTokens()` emits PAGE_BEGIN before reading a previously uncached page; a verified SEARCH from the same request/PID fixes distinct `pages_read` cardinality at the next PAGE_BEGIN, candidate index lower bound, and immutable PdfRenderer page count. Dart `cloudAwardNativeRunningEnvelopeViolation` now fails closed on PAGE_BEGIN page-read mismatch, candidate-index rollback, or page-count change; sparse new-page and forward-candidate progress remain valid. Added focused negative/positive unit regressions and a real temporary result-file/MethodChannel consumer rollback regression. This is UI progress evidence validation, NOT a native result-writer or global-negative-search repair.
- Native Gate B remains HOLD: same-request heartbeat/result writer race, terminal atomicity/durable custody, native Running/FAILED source+candidate SHA identity, FD-bound source custody, PID reuse, and ~87K-page global negative proof unresolved; zero/partial misses UNKNOWN. `NATIVE_WRITE_SAFETY_HOLD` persists for the specific rejected Kotlin payload (not retried). PR Draft/Merge HOLD; no release bump, official PDF/LKG/SQLite/POSTED NT$700/main untouched; `HOLD_NOT_READY_FOR_OWNER_DEVICE`.

## 2026-10-25 PR #45 sampled PAGE_BEGIN monotonicity correction — exact-head CI/Signed pending
- Root cause: Kotlin pageTokens() writes PAGE_BEGIN/SEARCH to one overwritten result file, while Dart polls every 50ms. A previously verified SEARCH pages_read=13 followed by observed PAGE_BEGIN pages_read=15 can be legitimate when intermediate SEARCH(14)/SEARCH(15) were not sampled. The prior strict equality check was a false-positive rejection.
- Minimal production change: PAGE_BEGIN now rejects only pages_read below the last observed verified SEARCH; retain source-byte, request/PID, stage, candidate-index rollback, immutable page-count, clock, and SEARCH page-identity guards. This permits sparse sampled progress but does not infer unseen pages as global negative coverage.
- Focused unit: PAGE_BEGIN(12) fails, (13/14/15) passes with prior SEARCH(13); candidate index and page-count mismatches still fail. Real temp-result-file/MethodChannel integration overwrites PAGE_BEGIN(13)→SEARCH(14)→PAGE_BEGIN(14)→SEARCH(15)→PAGE_BEGIN(15) between consumer polls, verifies PAGE_BEGIN(15) accepted, then cancels without COMPLETE or negative authority.
- Native Gate B still HOLD: same-request writer race, terminal atomicity/durable custody, Running/FAILED source/candidate SHA identity, immutable source custody, PID reuse and ~87K-page global negative proof remain unresolved. `NATIVE_WRITE_SAFETY_HOLD` applies to the specific previously refused Kotlin payload; it was not retried. PR OPEN/DRAFT/MERGE HOLD, version 4.20.36+494, `HOLD_NOT_READY_FOR_OWNER_DEVICE`; no main, formal ledger/SQLite, official PDF/LKG or posted NT$700 changes.

## 2026-10-25 PR #45 PAGE_BEGIN impossible full-cardinality rejection — source-bound Dart safety gate (exact-head CI/Signed pending)
- Prewrite authority: parent `4560cab1af311bb3456fce6e90f5398e1c35d1af`, PR #45 OPEN/DRAFT, version `4.20.36+494`. Kotlin `pageTokens()` returns cached pages without PAGE_BEGIN; for a previously uncached page it writes PAGE_BEGIN with `pagesRead.size` BEFORE `pagesRead.add(pageNumber)`. Therefore `PAGE_BEGIN.pages_read == page_count` is not producible by the current native worker.
- Minimal Dart fail-closed correction: `cloudAwardNativeRunningEnvelopeViolation` rejects `PLATFORM_RENDERER_PAGE_BEGIN` when `pages_read >= page_count`; unchanged SEARCH and sampled PAGE_BEGIN monotonicity permits legal 13→15 skipped intermediate observations. Added 87,000-page positive (86,999) and negative (87,000) unit cases plus a temporary result-file/MethodChannel consumer regression for 99/100 pre-read cardinality. This is envelope integrity only, not proof of native completion or global negative coverage.
- `NATIVE_GATE_B=HOLD`: result-writer heartbeat race, terminal durable atomicity, Running/FAILED source+candidate SHA, immutable source custody, PID reuse, and global negative proof remain unresolved; `NATIVE_WRITE_SAFETY_HOLD` still applies to the specific rejected Kotlin payload, which was not retried. Zero/partial misses remain UNKNOWN; no auto-post. PR Draft/Merge HOLD, `HOLD_NOT_READY_FOR_OWNER_DEVICE`; no release bump, main/formal ledger/SQLite/official PDF/LKG/POSTED NT$700 untouched. New exact-head CI and genuine Signed must be independently verified.

### 2026-10-25 — Native PAGE_BEGIN renderer-entry continuity (PR #45)

- **UI / Dart consumer**: `_findMatchesCrashIsolated` records a monotonic renderer-entry flag on each validated `PLATFORM_RENDERER_PAGE_BEGIN` or `PLATFORM_RENDERER_CANDIDATE_SEARCH` snapshot, not just sampled SEARCH. `cloudAwardNativeRunningEnvelopeViolation` rejects later SHA/opening stages once this flag is set; normal first opening and PAGE_BEGIN→SEARCH remain allowed. Focused unit and temp-result-file/MethodChannel tests cover this boundary.
- **Native Worker / persistence**: unchanged. Unjoined heartbeat, result-writer atomicity/terminal custody, source immutable snapshot/FD identity, PID reuse, and cross-page global negative coverage remain unverified. `NATIVE_WRITE_SAFETY_HOLD` and `HOLD_NOT_READY_FOR_OWNER_DEVICE` remain authoritative; this Dart guard is not Native Gate B closure.

### 2026-10-26 PR #45 — native startup ACK without first trusted result evidence (exact-head CI/Signed pending)
- Source-bound root cause: Android `startPlatformCandidateWorker` returns requestId/resultPath after service-start acceptance, before any native Running/result file or verified PID. Dart previously polled a never-created result file every 250ms or malformed pre-PID JSON every 50ms indefinitely; the PID-bound liveness probe intentionally cannot diagnose a worker with no trusted PID. Foreground refresh has no outer lookup deadline.
- Minimal Dart production correction: a conservative two-minute first-evidence observation deadline, injectable as Duration only through the test seam. If no validated Running or terminal arrives, raise `CLOUD_AWARD_CANDIDATE_WORKER_STARTUP_UNVERIFIED` (UNKNOWN/HOLD), never `PROCESS_DIED`, negative award authority, or formal posting. Valid Running disables only this startup deadline; existing heartbeat/PID liveness continues for long source hashing. Terminal validation, retained FAILED/malformed evidence, and cancellation priority remain intact.
- Five real temporary result-file/MethodChannel regressions: no-file ACK and malformed no-PID bounded UNKNOWN with zero liveness probes; verified Running not spuriously timed out; early FAILED retained; cancellation wins. No Kotlin code changed, no official PDF read, no version bump. `NATIVE_GATE_B=HOLD` for writer race, terminal atomic/durable custody, source/candidate SHA, immutable source custody, PID reuse and global negative proof; `NATIVE_WRITE_SAFETY_HOLD` remains. PR OPEN/DRAFT/Merge HOLD; main, posted NT$700, formal ledger/SQLite and PDF/LKG unchanged; `HOLD_NOT_READY_FOR_OWNER_DEVICE`.


### 2026-10-26 PR #45 — Android API35 native notification-channel test-only CI gate (expected RED until native review)
- Source: `PlatformPdfCandidateWorkerService.onStartCommand` invokes `startForeground(buildNotification(...))` before its worker try/catch, while `ensureNotificationChannel()` is defined but has no callsite in this service. `PdfiumCandidateWorkerService.onCreate` registers the same channel but its prior execution is not guaranteed. This is a **source-level fresh-install risk**, not a reproduced physical Android failure.
- This test-only change adds Robolectric API35 synthetic fresh-install/no-channel negative and preexisting-channel positive JVM tests, plugin test dependencies, and an explicit `:flutter_pdf_text:testDebugUnitTest` CI step. No production Kotlin, Dart, formal PDF, ledger, SQLite, or LKG changes. A red native test must remain visible as `NATIVE_NOTIFICATION_CHANNEL_HOLD`; do not skip or suppress it, and do not dispatch Signed on a failed exact-head full CI.
- The platform's previously refused Kotlin create_blob payload is not resubmitted or circumvented. A legitimate human Kotlin source review/platform safety approval is still required for a self-registering foreground channel and the independent Native Gate B writer race, atomic terminal, immutable source custody, PID reuse, and global negative proof. `HOLD_NOT_READY_FOR_OWNER_DEVICE`; PR OPEN/DRAFT, Issue #13 OPEN, main and posted NT$700 unchanged.


### 2026-10-27 PR #45 — native fresh-start notification-channel production correction (new CI pending)
- Before change, Android API35 Robolectric `freshInstallRegistersChannelBeforeFirstForegroundStart` failed at `PlatformPdfCandidateWorkerServiceNotificationChannelTest.kt:42`; preexisting-channel positive passed (old exact-head CI 40313966343, 2 JVM tests/1 FAIL). Production `onStartCommand` started foreground before calling already defined `ensureNotificationChannel()`.
- Narrow independent production fix: invoke existing idempotent `ensureNotificationChannel()` directly before `startForeground()` in the same Platform Service, without changing native Worker source identity, terminal writer, PDF search, ledger, or test assertions. Preserve the RED test as a required regression; new exact-head `Flutter Android CI` and true `workflow_dispatch` Signed must independently pass before test closure. This fix is separate from the previously blocked 2026-10-15 Kotlin Running SHA payload; it neither retries that payload nor completes native Gate B.
- Native SHA identity (Running/FAILED source+candidate), atomic durable terminal, multi-start ownership, PID reuse, immutable source custody and 87k-page global negative completeness all remain HOLD. App still `4.20.36+494`; no Owner Android UAT, no direct main changes, no PDF/SQLite/accounting/LKG mutations, PR OPEN/DRAFT/Merge HOLD.


### 2026-10-27 PR #45 — native OPEN_WAIT heartbeat quiescence before renderer/terminal progression (CI/Signed pending)
- Prewrite authority: exact parent `e6a30ca86f84c6e2ef5e7ef717e8d0180e48d188`, Flutter Android CI `40448102432` SUCCESS (Analyze, 2,054 Flutter tests, debug APK, API35 native notification-channel regression), true workflow_dispatch Signed `40448110036` SUCCESS with same-head artifact `12709703307`. This **prior-head** evidence is invalid for the new commit.
- Source-bound race: `PlatformPdfCandidateWorkerService.runLookup` previously used only `opening.set(false); openHeartbeat.interrupt()` both after `PdfRenderer` opens and in `finally`. An OPEN_WAIT writer already inside `writeRunning` could still overwrite a later OPEN_OK/COMPLETE/FAILED snapshot.
- Narrow native production correction: both shutdown paths now call `stopAndJoinPlatformOpenHeartbeat`, which first clears the opening flag, interrupts the heartbeat and waits until it is no longer alive; caller interruption cannot release the join early and is restored. This enforces same-heartbeat writer quiescence before the main worker continues; it is **not** global result-writer serialization or atomic durability.
- Native JVM focused positive/negative tests: sleeping heartbeat stops without a late write; in-flight uninterruptible synthetic write prevents stop returning until released; interrupted joining caller still waits and retains its interrupt status. Existing API35 Robolectric notification-channel tests remain unchanged and required in CI. No official PDF, Android device, accounting, SQLite, LKG, or posted NT$700 touched.
- Remaining `NATIVE_GATE_B=HOLD`: global single-owner writer, unique same-dir temp + atomic durable replace/fsync with injected rename failure, irreversible terminal identity (request/PID/source/candidate SHA), immutable source custody/FD, overlapping startId foreground ownership, PID reuse/native-exit lease and cross-page global negative-completeness proof. Zero/partial misses stay UNKNOWN; no auto-post. PR OPEN/DRAFT/Merge HOLD; version `4.20.36+494`; no Owner Android UAT. New exact-head CI and true Signed must be read back before claiming this subgate PASS.


### 2026-10-27 PR #45 — native atomic replacement and focused JVM execution (exact-head CI pending)
- Parent `94916f4b53b11b9bf564a112fd114cc8b4492e03`: Flutter Android CI `40460695387` SUCCESS (2,054 Flutter tests, debug build, selected channel regression); true workflow_dispatch Signed `40460703955` SUCCESS, artifact `12715377110`. All prior-head authority expires with the new commit.
- Source issue: native `writeAtomic` used a shared `.tmp` and on rename failure overwrote the target directly. Earlier CI `--tests` only selected the channel class; the prior heartbeat test class was not executed by that exact-head CI.
- Narrow production change: process-shared `PlatformResultAtomicWriter` serializes calls within one Android process, uses unique same-directory temporary files, file fd.sync, ATOMIC_MOVE+REPLACE_EXISTING without direct-write fallback, and Android Os.fsync on the parent directory. Exceptions propagate. Post-rename directory-fsync failure is ambiguous, not verified durable success.
- Four synthetic JVM tests cover unique temp/replace, injected rename failure preserving the trusted target, propagated parent-fsync failure, and same-writer serialization. CI now explicitly selects API35 notification channel (2), heartbeat stop/join (3), and atomic writer (4) test classes. Only new exact-head CI can establish these tests actually ran.
- Still HOLD: cross-process writer lease, terminal irreversible request/PID/source/candidate SHA authority, immutable FD custody, overlapping startId, PID reuse/process death, Android native durability fault tests, and 87K-page global negative proof. Zero/partial misses remain UNKNOWN; no auto-post. PR OPEN/DRAFT/Merge HOLD, Issue #13 OPEN, version 4.20.36+494, main/ledger/SQLite/official PDF/LKG/POSTED NT$700 unchanged; no Owner Android UAT.

### 2026-10-27 PR #45 — Android directory fsync SDK compile compatibility (exact-head CI required)
- Parent `ae22449809cb3cc47d52b15c86c5443331dc2cdf` CI `40465915481` failed at first actual error `PlatformResultAtomicWriter.kt:24:43 Unresolved reference 'O_DIRECTORY'` in `:flutter_pdf_text:compileDebugKotlin` during Build debug APK; Analyzer and 2,054 Flutter tests passed, native 9-test step was **SKIPPED**, not passed. True workflow_dispatch Signed `40465922535` failed exact-head authority; BuildInspect skipped; artifacts zero.
- Minimal source-bound correction: open parent directory with Android SDK-supported `OsConstants.O_RDONLY` instead of `O_RDONLY or O_DIRECTORY`; preserve `Os.fsync(fd)`, `finally Os.close(fd)`, same-dir unique temporary file, file fd sync, atomic move, exception propagation and no non-atomic fallback. A directory fd opened read-only can be fsynced on supported Android/Linux filesystems; any open/fsync/close failure must propagate and must **not** assert durable COMPLETE. Actual Android filesystem durability remains unproven.
- Existing CI-selected native regression classes remain intact (notification channel 2, heartbeat 3, atomic writer 4); compile blocker prevented their execution on parent HEAD. No test filtering/skip/masking, no version bump, no Android device or official PDF work. New HEAD must obtain new exact-head CI and true Signed before any artifact authority.
- Native Gate B still HOLD for cross-process writer lease, terminal irreversible identity/custody, overlapping startId, PID reuse, fault-injected Android durable fsync, and 87K-page global negative completeness; zero/partial misses UNKNOWN, no auto-post. PR OPEN/DRAFT/Merge HOLD, Issue #13 OPEN, version 4.20.36+494; main, ledger, SQLite, official PDF, LKG and POSTED NT$700 unchanged; Owner device NOT READY.

### 2026-10-27 PR #45 — single-Service foreground start ownership native subgate (new CI required)
- Parent exact-head `652216247845cedf7679dece40bc6193e018c410`: Flutter Android CI `40472882489` SUCCESS (Analyzer, 2,054 Flutter tests, Debug APK, selected channel/heartbeat/atomic JVM regression step). True same-head workflow_dispatch Signed `40472891782` Validate and BuildInspect SUCCESS, artifact `12721415597`; independent ZIP digest/CRC, APK SHA/CRC, manifest 4.20.36+494, signer pin and required/forbidden permissions checked. This evidence expires for the new commit.
- Source defect: `PlatformPdfCandidateWorkerService.onStartCommand` previously started a new thread and called `startForeground` for every startId, and each worker unconditionally called `stopForeground(true); stopSelf(startId)`; overlapping requestIds could stop one another's foreground or race to write the same result path.
- Narrow fail-closed native correction: a per-Service-instance `PlatformWorkerStartLease` accepts one nonblank requestId/resultPath/startId, rejects duplicate/overlapping starts without writing FAILED or spawning another worker, and permits only the exact owner token to tear down foreground. Cleanup holds the lease lock and closes the Service instance before any newer owner can acquire. Rejected starts produce no candidate authority; the caller must treat missing/partial result as UNKNOWN. This does not establish a cross-process file lock or durable terminal identity.
- Four synthetic JVM positive/negative tests cover overlapping/double starts, forged/stale owner token, concurrent cleanup/acquire barrier, and fail-closed cleanup exception/invalid inputs. The native CI selector adds this test class while retaining all prior 9 expected cases; new exact-head CI must prove execution. No official PDF, formal ledger/SQLite, LKG or POSTED NT$700 touched.
- Native Gate B remains HOLD: cross-process writer lease, terminal irreversible request/PID/source/candidate SHA custody, immutable FD snapshot, process death/PID reuse, Android real-device fsync fault injection, and 87K-page global negative completeness. Zero/partial miss=UNKNOWN, no auto-post. PR OPEN/DRAFT/Merge HOLD, Issue #13 OPEN, version 4.20.36+494, Owner device NOT READY.

### 2026-10-27 PR #45 — OS-held per-result native process lease (new exact-head CI/Signed required)
- Parent exact-head `b9f33ae86dcccd632bc74688d159ae8c5cfe2435`: Flutter Android CI [40487614850](https://github.com/easonliu714/my_finance_app_public/actions/runs/40487614850) SUCCESS (Analyze, 2,054 Flutter tests, Debug APK, selected 13 native JVM regressions). Genuine same-head workflow_dispatch Signed [40487626192](https://github.com/easonliu714/my_finance_app_public/actions/runs/40487626192) Validate/BuildInspect SUCCESS, artifact 12728302960 digest sha256:fb67d3c006ce8be041bdae0f3d0679c0f8bedff1e3a4a654f5bcd0912c2ac15a. Parent evidence expires on new HEAD; no Owner device release.
- New `PlatformResultProcessLease` obtains `FileChannel.tryLock` on a stable, never-deleted same-directory sidecar; rejects missing parent, symlinked target/sidecar, and contended lock. `PlatformWorkerStartLease` acquires this before foreground ownership and releases it after cleanup even on thrown cleanup. Rejected requests spawn no writer or false FAILED/COMPLETE. Four new OS-lock JVM positive/negative tests plus four preserved synthetic foreground-token tests; CI explicitly selects the new class (17 expected JVM cases total). This proves a native OS-lock mechanism only after new exact-head CI; not independent Android process-death/PID-reuse testing.
- Native Gate B HOLD: terminal immutable request/source/PID/candidate SHA, immutable source FD/snapshot, process death/PID reuse, cross-process independent-process tests, Android fsync fault injection, and 87K-page global negative completeness. Zero/partial=UNKNOWN, no auto-post. PR OPEN/DRAFT/Merge HOLD, Issue #13 OPEN, version 4.20.36+494. main, ledger, SQLite, official PDF, LKG, POSTED NT$700 unchanged. Owner NOT READY.


### 2026-10-27 PR #45 — native terminal-status monotonic fence (new exact-head CI required)
- Parent exact-head `acbec928ef0bcc07996a6da5f8c94dc946537de7`: Flutter Android CI [40495134543](https://github.com/easonliu714/my_finance_app_public/actions/runs/40495134543) SUCCESS (Analyze, 2,054 Flutter tests, Debug APK, selected channel/heartbeat/atomic/foreground/OS-lock JVM classes). Genuine workflow_dispatch Signed [40495142996](https://github.com/easonliu714/my_finance_app_public/actions/runs/40495142996) Validate/BuildInspect SUCCESS; artifact 12731098573, ZIP SHA256 60711eec380f9fc0048e2aeb5bbdde95c05858929c4cd875842ea3129eebd459; independent ZIP/APK CRC, APK SHA256 b3f91e3499889360ad88f500adfaeb0347df8542bf0df3f673aaedc7471189ab, manifest 4.20.36+494, signer pin and permissions checked. These are PARENT-HEAD evidence only, invalid for a new commit.
- Source-bound defect: a restarted worker or late native publisher could replace an existing COMPLETE/FAILED result using the otherwise atomic writer; the OS-held process lease alone cannot make terminal status irreversible across restarts. Production `PlatformResultAtomicWriter` now defaults to strict JSON transition validation: an existing COMPLETE/FAILED result cannot be overwritten, foreign-request RUNNING is rejected, and malformed/unknown/symlinked existing result fails closed. The existing four atomic filesystem tests explicitly exercise the atomic primitive with terminal guard disabled; seven NEW API35 Robolectric JVM tests cover the default production terminal fence, positive RUNNING→COMPLETE, stale/foreign/malformed/symlinked and post-fsync-ambiguity negatives. CI selects all six native classes (24 expected cases, NOT independently JUnit-XML-counted).
- Scope is terminal STATUS monotonicity under the existing per-result OS lock, NOT full request/PID/source SHA/candidate SHA custody or an unforgeable cross-process terminal identity. External deletion/replacement of the result/lock sidecar, process death/PID reuse, immutable source FD, real Android fsync fault injection, and 87K-page cross-page negative completeness remain HOLD. Zero/partial=UNKNOWN, no auto-post; version 4.20.36+494, PR OPEN/DRAFT/Merge HOLD, Issue #13 OPEN, main/SQLite/ledger/official PDF/LKG/POSTED NT$700 untouched, Owner NOT READY. New exact-head CI/Signed required.

## 2026-10-27 Native Terminal Fence Android SDK compilation and fixture correction (exact-head CI pending)
- Parent source authority: `f3f99a15506ee7c8d3571c6023cf24a1a66756f1` (PR #45 OPEN/DRAFT, main unchanged, version `4.20.36+494`). Exact-head Flutter CI run `40503391333` failed at `Build debug APK` on Android Kotlin compile: `PlatformResultAtomicWriter.kt:49:40 Unresolved reference 'readString'`; the `optString` errors were downstream. Analyze and 2,054 Flutter tests passed; native JVM step was SKIPPED, not PASS/FAIL. True Signed workflow_dispatch `40503400561` correctly failed Validate due to exact-head CI and produced no artifact.
- Minimal production fix replaces Android SDK-incompatible `Files.readString(target)` with UTF-8 `String(Files.readAllBytes(target), Charsets.UTF_8)` while retaining prior 1,048,576-byte cap, NOFOLLOW_LINKS, terminal status monotonicity, unique same-directory temporary file, atomic move, file/parent fsync, and fail-closed errors.
- Focused native test fixture correction: delete only two newly-created empty files before their initial writes in `failedTerminalCannotBeReplacedByComplete` and `foreignRequestCannotOverwriteExistingRunning`; keep malformed-prior negative and all seven terminal-fence cases, original native regressions and CI selection unchanged. New exact-head CI and independently validated true Signed required; no tests are waived.
- Scope remains native terminal STATUS fencing under per-result OS lease; cross-process death/PID reuse, immutable source FD/source/candidate SHA custody, terminal identity, Android durable fault injection and 87K-page global negative-completeness proof remain HOLD. Zero/partial=UNKNOWN; no auto-post. PR OPEN/DRAFT/Merge HOLD, Issue #13 OPEN, main/ledger/SQLite/official PDF/LKG/POSTED NT$700 unchanged, Owner NOT READY.


### 2026-10-27 PR #45 — native immutable snapshot / same-FD source custody (new exact-head CI required)
- Fresh parent authority: PR #45 HEAD `2011b6b327e8a8ae9b8b0857051f1ed93f5a7f16` OPEN/DRAFT, Issue #13 OPEN, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`. Exact-head Flutter CI [40510977747](https://github.com/easonliu714/my_finance_app_public/actions/runs/40510977747) SUCCESS (Analyze, 2,054 Flutter tests, Debug APK, selected six native JVM classes / 24 expected cases; JUnit XML not independently counted). True same-head workflow_dispatch Signed [40510988186](https://github.com/easonliu714/my_finance_app_public/actions/runs/40510988186) Validate/BuildInspect SUCCESS; artifact 12739572035, ZIP metadata digest sha256:31e749a28c356e3ede125c82b4013da30b00ac309e138c9e55c5b4715dcf5f70. This is PARENT evidence, not new HEAD delivery authority; ZIP/APK binary has not been independently rechecked in this run.
- Source-bound TOCTOU defect: `runLookup` previously hashed `source.inputStream()`, later reopened the caller-controlled pathname for `PdfRenderer`, and read `source.length()` again for COMPLETE. New `PlatformSourceSnapshotCustody` opens source with NOFOLLOW_LINKS once, copies bounded expected bytes into a unique app-private cache snapshot, fsyncs it, opens independent hash/renderer FDs, unlinks snapshot before SHA-256 verification, and hands the same unlinked snapshot inode to `PdfRenderer`. COMPLETE reports verified snapshot bytes/SHA, not mutable pathname metadata. Copy/read failures, symlinks, wrong size/SHA, or missing private cache fail closed. This requires additional temporary space and does not prove process-death orphan cleanup or Android physical durability.
- Five new API35 Robolectric native positive/negative cases cover FD survival after pathname replacement/truncate, deterministic pathname swap during copy, in-place truncation during copy, symlink rejection, and SHA/byte mismatch with snapshot cleanup. CI selector retains all prior native classes and adds source custody (29 expected cases, not independently JUnit-XML-counted). New exact-head CI and genuine Signed are required; tests cannot be masked/skipped.
- HOLD remains for adversarial same-UID mutation of open FDs, independent Android process-death/PID reuse, external sidecar/target replacement, complete terminal request/PID/source/candidate SHA identity, device fsync fault injection, cache orphan cleanup, and ~87K-page global negative completeness (zero/partial=UNKNOWN; no auto-post). PR OPEN/DRAFT/Merge HOLD, version 4.20.36+494, Owner Android NOT READY. main/ledger/SQLite/135200798-byte official PDF/LKG/POSTED NT$700 untouched.


### 2026-10-27 PR #45 — source custody static contract repair + precise SHA failure semantics (exact-head CI pending)
- Parent authority: `d54b63cc45e789bd4f861b997e1fc440b6b8be4a`, PR OPEN/DRAFT, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`, Issue #13 OPEN. Exact-head Flutter CI [40520004346](https://github.com/easonliu714/my_finance_app_public/actions/runs/40520004346) failed at first red `Run tests` (2,050 passed, four stale cross-file static contract failures); Analyze PASS, Debug APK/native JVM SKIPPED. True same-head Signed [40520017573](https://github.com/easonliu714/my_finance_app_public/actions/runs/40520017573) correctly failed exact-head Validate, BuildInspect SKIPPED, artifacts=0. No prior Signed artifact can authorize this HEAD.
- Four Flutter contract assertions now explicitly bind `PlatformPdfCandidateWorkerService` to `PlatformSourceSnapshotCustody.capture`, `custody.descriptor` and `custody.bytes`/`custody.sha256`, while asserting the custody implementation's NOFOLLOW_LINKS, read-only ParcelFileDescriptor, unlink, length and SHA failure controls; no guard or negative assertion removed. CI first executes these four focused tests with failure log retained, then the original full Flutter suite and native regressions.
- Production maps only `IOException("SOURCE_CUSTODY_SHA256_MISMATCH")` to the stable external `PLATFORM_WORKER_SOURCE_SHA256_MISMATCH` FAILED code; all other IO errors retain generic failure and cannot become COMPLETE. Added native positive/negative classification test; source custody tests expected 6 (total selected native cases expected 30, JUnit XML not independently verified). Source snapshot custody and all prior native tests retained.
- New exact-head Flutter Analyze/focused/full/Debug APK/native tests and true workflow_dispatch Signed/Artifact are REQUIRED, not pre-certified. Native Gate B still HOLD: independent Android process death/PID reuse, same-UID sidecar/target replacement, complete terminal request/PID/source/candidate SHA identity, cache orphan cleanup, device fsync fault injection and ~87K-page global negative completeness remain unproven (zero/partial=UNKNOWN, no auto-post). Owner NOT READY; PR Draft/Merge HOLD; main, ledger, SQLite, official 135200798-byte PDF, LKG and posted NT$700 unchanged.


### 2026-10-28 PR #45 — nullable source snapshot FD ownership handoff (production fix committed; exact-head CI pending)
- Parent authority `48adc39ddd58d2bddb14dc6775a3450b5d6b93ae`, version `4.20.36+494`, Issue #13 OPEN, PR OPEN/DRAFT/Merge HOLD. Exact-head Flutter CI [40529787823](https://github.com/easonliu714/my_finance_app_public/actions/runs/40529787823) first failed at step 17 Debug APK: `PlatformPdfCandidateWorkerService.kt:255:30 Argument type mismatch: ParcelFileDescriptor? vs ParcelFileDescriptor`. Analyze, four focused Flutter contracts and full 2,054 Flutter tests PASS; native 30 expected tests SKIPPED, not FAIL/PASS. Same-head workflow_dispatch Signed [40530069732](https://github.com/easonliu714/my_finance_app_public/actions/runs/40530069732) correctly failed exact-head Validate; BuildInspect SKIPPED, artifacts=0.
- Production `runLookup()` now checks nullable `descriptor` into `rendererDescriptor` with `IOException("SOURCE_CUSTODY_DESCRIPTOR_MISSING")` before `PdfRenderer(rendererDescriptor)`, then relinquishes the local FD only after constructor success. The existing `finally` closes the renderer or still-owned descriptor, including failure paths; no `!!`, swallow, SHA bypass, skipped test, or weaker custody contract. Four existing Flutter cross-file source contracts now assert guarded handoff ordering and cleanup rather than the old nullable constructor call. Snapshot NOFOLLOW_LINKS, verified bytes/SHA, unlinked FD, OS lease, terminal immutable, atomic rename/fsync and prior native regressions remain.
- New exact-head Flutter Analyze/focused/full/Debug APK/native JVM (30 expected, JUnit XML independent count pending) and true workflow_dispatch Signed/ZIP/APK identity remain REQUIRED, not pre-certified. Native Gate B remains HOLD for independent process death/PID reuse, sidecar/target replacement, full terminal request/PID/source/candidate SHA identity, snapshot orphan cleanup, Android fsync durability and ~87K-page global negative completeness (zero/partial=UNKNOWN; no auto-post). Owner NOT READY. main, ledger, SQLite, official 135200798-byte PDF, LKG, posted NT$700 unchanged.


### 2026-10-28 PR #45 — Native result PID/process-epoch transition fence (production + JVM, CI pending)
- Authority before change: PR HEAD `097081e411ea0b9c409c414725a315ab9dfa36d3`, PR OPEN/DRAFT, main unchanged, Issue #13 OPEN, `4.20.36+494`. Exact-head Flutter Android CI [40538950897](https://github.com/easonliu714/my_finance_app_public/actions/runs/40538950897) SUCCESS (Analyze, 2,054 Flutter tests, Debug APK, Gradle native step; 30 expected native cases, individual JUnit XML not independently counted). True same-head workflow_dispatch Signed [40538963605](https://github.com/easonliu714/my_finance_app_public/actions/runs/40538963605) SUCCESS with artifact 12752306368; artifact metadata digest `44888292a4f855e635c1349053429183f84c109f8172231edd20ed2404c28072`. No independent ZIP CRC / signer re-download in this gate; not Owner READY.
- Native production result publishing now requires positive integer `worker_pid` and a canonical process-epoch UUID for every RUNNING/COMPLETE/FAILED payload. Under the existing per-result OS lease, a prior RUNNING result can only transition for the same request_id, PID and process epoch; PID reuse with a new process epoch and missing/malformed/foreign identity fail closed. The process epoch is randomly generated once per Android process, not a secret or cryptographic proof. New API35 Robolectric native positive/negative tests cover valid RUNNING→COMPLETE/FAILED, foreign PID/request, reused PID/different epoch, missing/malformed/legacy identity and terminal immutability; CI selector includes them. Existing terminal status, source FD custody, atomic fsync and Flutter tests remain unchanged.
- New exact-head full Flutter/Debug APK/native JVM and true Signed are REQUIRED, not pre-certified. This is a narrow native transition fence, NOT proof against same-UID target/sidecar replacement, independent Android process death, forged JSON, immutable source/candidate SHA terminal binding, snapshot orphan cleanup, Android fsync fault injection or ~87K-page global negative completeness. Zero/partial miss=UNKNOWN, no auto-post. PR Draft/Merge HOLD, Owner NOT READY, main/ledger/SQLite/official 135200798-byte PDF/LKG/posted NT$700 untouched.


### 2026-10-28 PR #45 — Terminal digest syntax / prior-RUNNING sub-Gate (Native B HOLD)
- Fresh parent `b437f4bb6ce325b20ae6eca6938dd6875c489acd` OPEN/DRAFT, version `4.20.36+494`. Parent exact-head Flutter Android CI [40548897713](https://github.com/easonliu714/my_finance_app_public/actions/runs/40548897713) SUCCESS: Analyze, focused/full 2,054 Flutter tests, Debug APK and Gradle native task (38 selected native cases expected, no independently counted JUnit XML). True same-head Signed [40548909694](https://github.com/easonliu714/my_finance_app_public/actions/runs/40548909694) SUCCESS, artifact 12756645675, metadata ZIP SHA256 `57664e25e82539526e9799b82d7d13dfc69f6bc9fe8bd0f3e41a3ae6687138f6`; no independent binary ZIP CRC/signature re-download in this gate.
- Strict production `PlatformResultAtomicWriter` now requires a prior RUNNING and valid 64-hex source_sha256 and candidate_universe_sha256 for COMPLETE. Early FAILED without verified source remains legal and does not fabricate SHA. Existing request/PID/epoch, terminal immutability, OS lease, snapshot custody and atomic fsync retained. Seven API35 Robolectric positive/negative cases added to native CI selector (45 expected native cases; individual XML count pending).
- Deliberately narrow sub-Gate only: digest equality against RUNNING, same-UID forgery resistance, independent process death/PID reuse, sidecar/target replacement, orphan cleanup, Android fsync durability and ~87K-page global negative completeness remain HOLD. No retry/repackaging of 2026-10-15 specifically safety-rejected Kotlin Running-SHA payload. Zero/partial miss=UNKNOWN; no auto-post, no Owner APK delivery. New exact-head CI/Signed REQUIRED, not pre-certified.


### 2026-10-28 PR #45 — Native snapshot orphan cleanup under OS-held copy lock (Gate B HOLD)
- Parent HEAD `8384d4aba55b7bd0059345a158220e26d741dbaa`: Flutter Android CI [40559430943](https://github.com/easonliu714/my_finance_app_public/actions/runs/40559430943) SUCCESS (Analyze, 2054 Flutter tests, Debug APK, Gradle native task; 45 native expected, individual JUnit XML not independently counted). True same-head workflow_dispatch Signed [40559444924](https://github.com/easonliu714/my_finance_app_public/actions/runs/40559444924) SUCCESS, artifact 12762112752, ZIP metadata SHA256 `6d501e143b6b2ae135e3c40a4c81f393d966cca1ecdf6fdef1c0329eb78201e0`; binary CRC/signer not independently re-downloaded. Version `4.20.36+494`.
- Production `PlatformSourceSnapshotCustody`: hold exclusive OS lock during named snapshot copy; on subsequent capture, remove only app-private matching regular snapshots older than 24h if lock obtainable; preserve fresh, locked, symlink and unrelated files. Retain verified unlinked FD, SHA, byte-count checks and fail-closed semantics. Four API35 Robolectric tests added; CI selector 49 expected native cases, not yet individually verified.
- Narrow orphan cleanup only: independent Android process death/PID reuse, same-UID hostile replacement, full terminal RUNNING/source/candidate digest equality, fsync fault injection and ~87K-page global negative completeness remain HOLD. Specifically safety-rejected 2026-10-15 Kotlin Running-SHA payload must never be resent/repackaged; normal human review required for overlap. New exact-head CI and true Signed are required. Zero/partial=UNKNOWN; no auto-post, no Owner delivery, main/ledger/SQLite/official 135200798-byte PDF/LKG/posted NT$700 untouched.


### 2026-10-28 PR #45 — Orphan cleanup deterministic test-clock fixture repair (exact-head CI pending)
- Parent `e82021bb43f11a467251c5092337925caaa0af6e` Flutter Android CI [40567764038](https://github.com/easonliu714/my_finance_app_public/actions/runs/40567764038) FAILURE: Analyze, focused/full 2,054 Flutter tests and Debug APK PASS; native Gradle 49 tests, 1 failed at `PlatformSourceSnapshotOrphanCleanupTest.kt:42` (staleUnlockedOrphanIsRemovedButFreshAndUnrelatedFilesRemain). Full original job log reviewed. Same-head workflow_dispatch Signed [40567775053](https://github.com/easonliu714/my_finance_app_public/actions/runs/40567775053) correctly FAILED authority; no signed artifact.
- Root cause: deterministic `now=1_800_000_000_000L` is later than CI-created fresh file mtime, so unaged fresh fixture was also eligible for 24h pruning. Test-only source fix pins fresh file mtime to `now` before asserting exactly one stale removal. Preserve four native tests and production 24h cutoff, OS-held copy lock, no-follow SHA/FD custody unchanged.
- New exact-head Flutter/Android native CI and true same-head Signed must pass before claiming test closure. Individual JUnit XML and Android real-device durability not independently established. Native Gate B and ~87K-page global negative completeness remain HOLD; zero/partial=UNKNOWN, no auto-post or Owner APK delivery. PR DRAFT/Merge HOLD; main, official PDF/LKG, SQLite/ledger and posted NT$700 untouched.


### 2026-10-28 PR #45 — Result-parent NOFOLLOW sub-Gate (Native B HOLD)
- Fresh parent `8a89d8afbfdd1bbd89b7df11fb71e0c47f3d0e38`: exact-head Flutter Android CI [40576893631](https://github.com/easonliu714/my_finance_app_public/actions/runs/40576893631) SUCCESS (Analyze, focused/full 2,054 Flutter tests, Debug APK and Gradle native task; 49 expected cases, individual JUnit XML not independently counted). True same-head workflow_dispatch Signed [40576904670](https://github.com/easonliu714/my_finance_app_public/actions/runs/40576904670) SUCCESS; artifact 12770306354 ZIP metadata digest `a6a62ecba7d425eae3980dfd1525517272c77ada4b2458bb02f28993dc853643`, not independently binary re-downloaded. Version remains `4.20.36+494`.
- Narrow production hardening: `PlatformResultAtomicWriter.write` rejects a direct symlink/non-directory result parent before creating temp files or replacing result; `PlatformResultProcessLease.tryAcquire` rejects the same symlink/non-directory parent rather than following it into a different lock directory. Four API35 Robolectric tests exercise redirected symlink rejection, non-directory rejection, real-directory exclusive lease and safe ordinary directory creation. CI selector adds the class (53 expected native cases; exact-head CI not yet certified).
- This is only a direct-parent no-follow boundary. Ancestor-symlink races, same-UID parent/sidecar/target replacement after check, independent process death/PID reuse, terminal RUNNING/source/candidate digest equality, Android fsync durability and ~87K-page global negative completeness remain HOLD. Zero/partial miss=UNKNOWN; no auto-post or Owner delivery. The specifically rejected 2026-10-15 Kotlin Running-SHA payload was not reused, transformed or retried. PR DRAFT/Merge HOLD; main, official 135200798-byte PDF/LKG, SQLite/ledger and posted NT$700 untouched. New exact-head CI and true Signed required.

### 2026-10-28 PR #45 — Sidecar inode replacement during OS-lock acquisition (narrow Native B sub-Gate; pending exact-head CI)
- Parent `7a0dfa2d3e2e28fc2c4ee2db4efeb2434d46e0ba` verified OPEN/DRAFT, version `4.20.36+494`. Exact-head Flutter Android CI [40585091889](https://github.com/easonliu714/my_finance_app_public/actions/runs/40585091889) SUCCESS (Analyze, focused/full 2054 Flutter tests, Debug APK and Gradle native task; 53 selected native cases expected, individual JUnit XML not independently verified). True workflow_dispatch Signed [40585103597](https://github.com/easonliu714/my_finance_app_public/actions/runs/40585103597) SUCCESS, same HEAD artifact 12771759245, ZIP metadata SHA256 `5292c82f427a32b15ae7d7708fbdd547754ba81ee8df5f785c8d3230ce917029`; no independent ZIP CRC/APK signer binary verification.
- Production `PlatformResultProcessLease.tryAcquire` now compares no-follow regular sidecar fileKey before and after OS tryLock, rejects a replaced/unlinked/symlinked sidecar in that bounded window and releases the old kernel lock. Three JVM positive/negative regressions inject rename, symlink swap and unchanged exclusive lock; existing CI selector already includes this test class (56 expected cases, independent JUnit XML pending). This is an actual production change, not docs-only.
- Scope is deliberately narrow: sidecar replacement after acquisition returns, ancestor-symlink races, process death/PID reuse on an Android device, source/candidate terminal digest equality, durable fsync fault injection and ~87K-page global negative completeness remain HOLD. The specifically safety-rejected 2026-10-15 Kotlin Running-SHA payload was not retried or transformed. Zero/partial=UNKNOWN, no auto-post/Owner APK delivery. PR Draft/Merge HOLD, main/ledger/SQLite/135200798-byte official PDF/LKG/posted NT$700 untouched.


### 2026-10-28 PR #45 — Same-VM held-sidecar replacement re-entry fence (narrow Native B sub-Gate; exact-head CI pending)
- First fresh-read: PR #45 OPEN/DRAFT head `f28ad1e336f7c920c9dbc83a2a18d438e9731fb9`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, pubspec `4.20.36+494`, Issue #13 OPEN. Parent exact-head Flutter CI [40593758665](https://github.com/easonliu714/my_finance_app_public/actions/runs/40593758665) SUCCESS (Flutter 2054, Analyze, Debug APK, native Gradle; 56 expected native cases, individual JUnit XML not independently counted). True same-head workflow_dispatch Signed [40593767569](https://github.com/easonliu714/my_finance_app_public/actions/runs/40593767569) SUCCESS, artifact 12776208218; binary ZIP CRC/APK signer not independently verified, version below Owner minimum.
- Source-bound deterministic local JDK reproducer confirmed that a first OS lock on an inode and a second OS lock on a replacement sidecar inode can both succeed after a pathname rename (`FIRST_LOCK=true SECOND_LOCK_AFTER_SIDECAR_SWAP=true`). The existing acquisition-only fileKey checks do not prevent this after lease return.
- Production `PlatformResultProcessLease.tryAcquire` now reserves the normalized result path in a synchronized same-VM registry before opening the replaceable sidecar, and releases that reservation on all failed acquisitions or an idempotent lease close. Four native JVM positive/negative tests cover held sidecar rename/replacement, unlink, rejected acquisition recovery, and repeated-close isolation; native selector remains the same test class (60 expected cases). No OS-held kernel lock or prior inode check is removed.
- **Scope limitation:** this is a same-VM re-entry fence, NOT a cross-process or same-UID malicious replacement proof. Independent Android process death/PID reuse, same-UID parent/target/sidecar replacement, terminal RUNNING/source/candidate digest equality, Android fsync fault injection and ~87K-page global negative completeness remain HOLD. Zero/partial=UNKNOWN, no auto-post or Owner APK delivery. The 2026-10-15 safety-rejected Running-SHA payload was not retried or transformed. PR DRAFT/Merge HOLD; main, official PDF/LKG, SQLite/ledger and posted NT$700 untouched.

### 2026-10-29 C13 — Terminal-progress post-hash mutation regression (narrow source-custody sub-Gate)
- Fresh PR parent `dc30c407ace69039e8b1f78c20302acf8ade24a4` is an actual test-only C13 RED commit. Exact-head Flutter Android CI [40725021559](https://github.com/easonliu714/my_finance_app_public/actions/runs/40725021559) FAILED specifically at Gradle native `PlatformSourceSnapshotCustodyTest.terminalProgress...` predecessor `postHashHeldWritableSnapshotFdNeverBecomesVerifiedRendererAuthority` (61 tests, 1 failure; ComparisonFailure line 177); Flutter Analyze, 2054 Flutter tests, Debug APK succeeded. This is a real Robolectric API35 JVM RED witness, not Android independent-process proof.
- This source change moves the untrusted terminal `onProgress(expectedBytes)` callback before the authoritative snapshot SHA read. A pre-opened writable FD mutation triggered by the callback must now produce `SOURCE_CUSTODY_SHA256_MISMATCH` instead of returning mismatched `VerifiedSource`. Native regression asserts exact fail-closed reason and a clean positive terminal-progress capture. No old Kotlin Running-SHA payload was retried.
- **Unclosed:** arbitrary same-UID writers retaining an FD after the final hash, cross-process Android/real-device behavior, atomic result parent/temp inode custody, fsync-after-move recovery, lease path aliases, PID/epoch/terminal digest equality, and ~87K-page global negative proof. No full Native Gate B or Owner UAT claim; Android native real-device proof HOLD, PR OPEN/DRAFT/Merge HOLD. Version `4.20.36+494` below required `4.20.37+495`. No official PDF/LKG, ledger/SQLite, posted NT$700, main, or auto-post changes. New exact-head CI must independently PASS before considering any next gate.

### 2026-10-29 C12 — Bounded post-move content readback (narrow detection only; Native Gate B HOLD)
- Fresh parent `bf680fcb67e67008440bb453b97ce6e8a99f1b0c`, PR #45 OPEN/DRAFT, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, pubspec `4.20.36+494`, Issue #13 OPEN. Exact-head Flutter Android CI [40745590361](https://github.com/easonliu714/my_finance_app_public/actions/runs/40745590361) failed at native Gradle step 19: 63 tests, one intentional C12 RED `PlatformResultAtomicWriterTest.parentReplacementCannotPublishForeignTemporaryInode` at line 141; Flutter Analyze, 2054 tests, Debug APK passed. No true same-head Signed release authority for this RED head.
- Production `PlatformResultAtomicWriter.write` now performs bounded 8KiB NOFOLLOW post-move byte-for-byte readback against its own UTF-8 payload before parent fsync and successful return. A replaced temporary inode is rejected with `RESULT_PUBLICATION_CONTENT_MISMATCH` (other readback IO errors fail closed). The existing parent-replacement witness now requires explicit rejection and still asserts `FORGED_RESULT` remains VISIBLE; an additional native test injects same-parent temp tampering and requires rejection without parent sync. The normal positive writer tests remain.
- **Scope limitation:** this is detection of false-success return, NOT prevention of a forged terminal file becoming visible, nor a defense against arbitrary same-UID pathname/FD replacement after readback. A consumer may observe the forged result before failure; post-move fsync failure remains durable UNKNOWN. Do not call C12 publication integrity CLOSED or Native Gate B PASS. Android API35 independent-process/instrumented proof, stable logical identity/kernel ownership, FD-anchored publication, trusted durable receipt/recovery, source/candidate digest equality and ~87K-page global negative completeness remain HOLD. Zero/partial=UNKNOWN; no auto-post, Owner APK, or merge. The 2026-10-15 specifically refused Running-SHA payload was not retried. Formal PDF/LKG, SQLite/ledger, posted NT$700 and main untouched. New exact-head CI must be read before any sub-Gate claim.

### 2026-10-29 C12/Cross-process Android API35 instrumentation preparation (compile-only, RED not executed)
- Fresh source-bound PR head `b31c5f7f782e9ec1cb4252c454f1d39609a8f538`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`, Issue #13 OPEN. Exact-head Flutter Android CI [40748364739](https://github.com/easonliu714/my_finance_app_public/actions/runs/40748364739) SUCCESS (2054 Flutter, Native Gradle); true Signed `workflow_dispatch` [40748376841](https://github.com/easonliu714/my_finance_app_public/actions/runs/40748376841) had Validate SUCCESS / BuildInspect in progress at preflight; not an Owner release authority.
- Added **debug-only, non-exported separate-process Android Messenger service** and `src/androidTest` API35 positive/negative lease cases: `unchangedSidecarRejectsSecondAndroidProcessUntilRelease` and `sidecarReplacementCannotCreateSecondAndroidOwnerWhileFirstAlive`. Assert different PID, same UID, OS lease exclusion, and sidecar rename/replacement double-owner negative. The latter is **expected RED** against current production `PlatformResultProcessLease` when run on Android. Test uses isolated cache, not ledger/PDF.
- CI now builds `:flutter_pdf_text:assembleDebugAndroidTest` in addition to existing native JVM regressions. **Compilation is not device execution.** `ANDROID_NATIVE_REAL_DEVICE_PROOF_HOLD` remains until actual API35 instrumented execution supplies JUnit XML, PID/UID/SELinux context, logcat, and content/durability assertions. This is a preparatory Android cross-process lease witness, not closure of C12 publication or C13 immutable FD.
- **No production lease/atomic writer change in this test-only gate.** C12 forged visible result, C13 post-hash arbitrary FD writer, parent/temp inode custody, fsync recovery, terminal source/candidate SHA equality, and ~87K-page negative completeness all HOLD. Zero/partial=UNKNOWN, no auto-post, no Owner APK, no merge; official PDF/LKG, posted NT$700, SQLite/ledger and main untouched. Await exact-head CI compile evidence.

### 2026-10-29 C12 Android API35 true emulator execution Gate (expected RED; no false PASS)
- Following the compile-only instrumentation at PR HEAD `4639b6dafe61c46c123ea3567c5675aa6b938d4a`, add a PR#45-scoped GitHub Actions job using a SHA-pinned Android Emulator Runner v2.38.0 (`a421e43855164a8197daf9d8d40fe71c6996bb0d`) and API35 google_apis x86_64. It checks out the exact PR head, requires KVM, and runs `:flutter_pdf_text:connectedDebugAndroidTest` for `PlatformResultProcessLeaseInstrumentedTest`; no skip, continue-on-error, or simulated Android PASS.
- The instrumented regression records independent PID, same UID and Android SELinux context; normal exclusion and recovery are positive controls. Sidecar pathname replacement while A holds the original inode must **deny B**; current production is expected RED. Evidence is JUnit XML, logcat and emulator API/SELinux status, uploaded even on failure. The job must actually execute and be independently read before assigning a result.
- This is **not** a production lease repair, C12 atomic publication closure, C13 arbitrary post-hash FD immutability, or a real phone PASS. Android real-device evidence, same-UID hostile process, parent/temp inode custody, fsync durable recovery, terminal source/candidate SHA and ~87K-page negative completeness remain HOLD. No signed Owner APK, no auto-post, no main/ledger/SQLite/official PDF/LKG changes; PR OPEN/DRAFT/Merge HOLD.
- API35 emulator execution attempt [40762371495](https://github.com/easonliu714/my_finance_app_public/actions/runs/40762371495) failed at the **KVM setup step**, exit 1 after udev rule creation; Android test was not launched, so no Android runtime RED/GREEN proof. The next source change replaces unreliable udevadm reload/trigger with an explicit `/dev/kvm` character-device preflight and direct ephemeral runner permission grant (`chmod a+rw`), preserving fail-closed KVM missing behavior and JUnit/logcat evidence. This is a CI environment repair, not a Native production safety repair.
- The first KVM-permission repair run [40762543589](https://github.com/easonliu714/my_finance_app_public/actions/runs/40762543589) passed the KVM preflight and entered the emulator-runner step, which then reported FAILURE before the job log became available; its unconditional `adb logcat -d` evidence collector remained in progress without an attached device. A bounded ADB availability probe and timeouts are added so that any emulator setup failure completes promptly with the original job log and an explicit `ANDROID_API35_ADB_DEVICE_UNAVAILABLE` marker. Root cause of emulator action remains unclassified until the full original log is read; no Android test PASS claimed.
- CI workflow authoring correction: an intermediate source replacement mistakenly expanded a JavaScript replacement-string `$'` token into a duplicated workflow tail, suppressing the Flutter Android CI trigger for that intermediate HEAD. The replacement is now generated using a literal callback, verified by exact Git blob readback, and restores a single valid upload step plus bounded ADB evidence collection. This is a workflow integrity repair, NOT an Android runtime PASS or production lease fix.

- **2026-10-29 05:19 Asia/Taipei / C14 API35 runtime CI shell compatibility:** exact-head Flutter Android CI [#40763834458](https://github.com/easonliu714/my_finance_app_public/actions/runs/40763834458) has Analyze/Test/Debug APK/native JVM/instrumentation compile PASS, but its actual Android API35 job FAILS at `reactivecircus/android-emulator-runner` script startup: emulator successfully boots (`sys.boot_completed=1`), then `/usr/bin/sh: 1: set: Illegal option -o pipefail` (exit 2) **before any instrumented test**. This change replaces only the runner's script prologue with POSIX `set -eu` (not a test skip/mask); normal shell steps remain Bash with `set -euo pipefail`. Android independent-process lease RED/GREEN, JUnit, logcat and kernel ownership remain **HOLD until new exact-head CI executes**. Production Kotlin unchanged; PR OPEN/DRAFT/Merge HOLD, version 4.20.36+494, no Owner APK, no ledger/PDF/LKG writes.

- **2026-10-29 05:28 Asia/Taipei / C14 second first-failure correction:** API35 emulator did boot and run `/usr/bin/sh` after previous correction on [#40771136533](https://github.com/easonliu714/my_finance_app_public/actions/runs/40771136533), but instrumentation **did not start**: original Android job log reports `Task '\\' not found in root project 'android'` (Gradle exit 1). `reactivecircus/android-emulator-runner` dispatches individual script lines via `sh -c`; YAML backslash-newline Gradle continuation became an argument instead of a shell continuation. The instrumentation Gradle command is now a single shell line; no native assertion is skipped and no Android security PASS is claimed. C12/C13/ownership and durable-recovery Gate B remain HOLD, pending a new exact-head runtime JUnit/logcat proof. No production/test Kotlin change, no main/ledger/PDF writes.


### 2026-10-29 C15 kernel abstract-socket dual-identity ownership candidate (CI pending)
- Fresh authority before change: PR HEAD `5865037f98779e8723641977d3f70041a68179c3`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, Issue #13 OPEN, version `4.20.36+494`. Exact-head Flutter Android CI [#40772917410](https://github.com/easonliu714/my_finance_app_public/actions/runs/40772917410): Analyze/2054 Flutter/debug APK/native JVM/instrumentation compile SUCCESS; Android API35 instrumentation **RED** (1 PASS, 1 FAIL) with `CROSS_PROCESS_DOUBLE_OWNER_AFTER_SIDECAR_SWAP`. True same-head Signed dispatch [#40772929261](https://github.com/easonliu714/my_finance_app_public/actions/runs/40772929261) FAILS at exact-head CI authority, no release artifact.
- Engineering candidate: bind both lexically normalized and canonical-parent-derived SHA256 Android abstract-namespace `LocalServerSocket` names **before** opening replaceable sidecar; retain until lease close. Bind failure/exception fails closed; never falls back to file lock alone. The existing Android RED must turn GREEN in new exact-head CI; no PASS claim until original JUnit/logcat readback.
- JVM tests use explicitly injected synthetic binders (not Android kernel proof) and add fail-closed bind failure and ancestor alias regressions; API35 independent-PID ancestor alias instrumentation is added. This is a bounded ownership candidate, not full trusted-root or same-UID security closure.
- Remaining HOLD: trusted app-private stable root, hostile same-UID pathname/FD swaps, prebind DoS, PID reuse/SIGKILL recovery, C12 FD-anchored publication/durable receipt, C13 arbitrary writable FD, terminal source/candidate digest equality, ~87K-page global negative completeness and real phone evidence. `ANDROID_NATIVE_REAL_DEVICE_PROOF_HOLD`; no auto-post, Owner APK, merge, main/ledger/SQLite/official PDF/LKG changes. October 15 refused payload not retried.


### 2026-10-29 C15 Android API35 real kernel GREEN / JVM boundary first-failure repair
- At exact PR HEAD `ac51cc907cda1b8184c63a2eb3c6eff5272d2a30`, [Flutter Android CI #40778320328](https://github.com/easonliu714/my_finance_app_public/actions/runs/40778320328) independently executed **three Android API35 emulator instrumentation cases, 3 PASS / 0 FAIL / 0 SKIP**: normal cross-PID exclusion/recovery, sidecar replacement no second owner, and ancestor alias no second owner. JUnit XML and artifact ZIP CRC/SHA independently read: artifact ID `12855404793`, SHA256 `39f4e4c08dcc07177f7b14ca972b624445e382bf166275e91a1dd43a74195c37`. This is real Android emulator kernel evidence, **not** physical phone proof, not all adversarial cases. The post-emulator evidence collector reported `ANDROID_API35_ADB_DEVICE_UNAVAILABLE` because the emulator had shut down; actual PID/UID assertions passed in JUnit, but raw logcat/PID values remain an evidence gap.
- Same-head Analyze/Flutter 2054 tests/debug APK PASS, but Native Gradle `:flutter_pdf_text:testDebugUnitTest` FAIL (66 tests, 2 failed) at `PlatformResultParentCustodyTest.realParentRetainsExclusiveLeaseAndValidRunningWrite` line 56 and `writerMayCreateNewOrdinaryParentBeforeLeaseAcquisition` line 77. Root cause: these preexisting Robolectric filesystem tests called the new production Android `LocalServerSocket` binder, which cannot be treated as a real Android kernel in Robolectric. **No production security fallback** is permitted.
- Repair only the JVM test harness to inject a deterministic synthetic kernel binder while preserving filesystem positive/negative assertions. The production `tryAcquire` continues to bind real Android sockets fail-closed; API35 instrumentation remains the authoritative runtime proof. Require new exact-head CI to demonstrate both jobs GREEN; no skip, masking, or blind rerun.
- All C12 publication-integrity, C13 hostile FD, durable recovery, stable trusted root, SIGKILL/PID reuse, prebind DoS, global ~87K-page negative completeness, and Owner Signed >=4.20.37+495 remain HOLD. PR OPEN/DRAFT, no main/ledger/SQLite/PDF/LKG write, no auto-post, no merge.


### 2026-10-29 C16 API35 prebind fail-closed test and in-emulator evidence capture (exact-head CI pending)
- Source authority before commit: PR HEAD `30780270def158529f0336fd5c192d092176a878`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, pubspec `4.20.36+494`, Issue #13 OPEN, PR OPEN/DRAFT. Previous exact-head CI [#40780157822](https://github.com/easonliu714/my_finance_app_public/actions/runs/40780157822) API35 instrumentation job SUCCESS (3 cases); main Analyze/Test/Build job was still in progress at preparation, so no overall CI PASS was asserted.
- Add API35 **real LocalServerSocket kernel prebind** negative/positive regression `preboundKernelIdentityDeniesLeaseWithoutSidecarThenRecovers`: prebind the exact lexical SHA256 abstract name; acquisition must fail closed without creating sidecar; close prebind then acquisition must succeed. This tests a bounded prebind failure/recovery invariant, **not** resistance to indefinite same-UID DoS.
- Collect API35 logcat/SDK/SELinux evidence *inside* the emulator runner before emulator shutdown, including after a failed native test; preserve the original Gradle nonzero exit status. Do not mask RED. This addresses prior `ANDROID_API35_ADB_DEVICE_UNAVAILABLE` post-emulator evidence gap.
- Gate remains HOLD pending new exact-head CI and independent JUnit/logcat readback. Android emulator is not a physical phone. C12 pathname/inode publication and fsync durable recovery, C13 arbitrary same-UID writable FD, trusted stable root, terminal digest equality, ~87K-page global negative completeness, Signed >=4.20.37+495, Owner UAT all HOLD. No auto-post, main/ledger/SQLite/PDF/LKG writes, merge, or APK delivery.


### 2026-10-29 C17 C12 forged-result visibility RED regression (pending exact-head CI)
- FIRST FRESH READ baseline PR `ee57994c8727f71e1abb7cba181d54b5e5401aeb`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`, Issue #13 OPEN, PR OPEN/DRAFT. Exact-head Flutter Android CI #40781786514 SUCCESS (Android API35 job and Analyze/Test/Build job); true workflow_dispatch Signed #40781796468 Validate SUCCESS, BuildInspect still running at readback; no Owner APK authority.
- Added **test-only deterministic C12 negative** `failedPublicationMustNotLeaveForgedResultVisible` in `PlatformResultAtomicWriterTest.kt`: inject parent rename/recreate and a forged temp pathname, assert the writer rejects content mismatch **and** that no forged result remains visible to a consumer. Existing production detects mismatch but currently leaves `FORGED_RESULT` at the public path; this assertion is expected RED and must not be skipped, weakened or converted into a false PASS. It tests a stronger consumer-facing invariant than the existing exception-only regression.
- Next Gate: obtain exact-head CI first-failed step, native JUnit XML and full original log; repair root publication integrity with Android-supported FD-anchored custody / durable recovery, not a post-hoc pathname check or blind deletion. Android API35 independent-process C12 publication test remains pending. No auto-post, formal ledger/SQLite/PDF/LKG/main writes, PR merge, release version bump or Owner APK. `ANDROID_NATIVE_REAL_DEVICE_PROOF_HOLD`.


### 2026-10-29 C18 Android API35 cross-PID C12 publication-integrity RED witness (CI pending)
- FIRST FRESH READ before code: PR HEAD `a4721f3e26fe4477ae793c5b5f37849c50303ab6`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, Issue #13 OPEN, version `4.20.36+494`. Exact-head Flutter Android CI [#40785656090](https://github.com/easonliu714/my_finance_app_public/actions/runs/40785656090) is **RED**: native Gradle 67 tests / 1 failed, first failure `PlatformResultAtomicWriterTest.failedPublicationMustNotLeaveForgedResultVisible` at line 191; Android API35 lease instrumentation job SUCCESS. True `workflow_dispatch` Signed [#40785666347](https://github.com/easonliu714/my_finance_app_public/actions/runs/40785666347) failed exact-head CI authority and produced no release artifact.
- C18 adds a scoped **debug-only** Messenger command to inject parent/temp pathname replacement from a *different Android PID with the same app UID*, plus Android API35 instrumentation positive `c18NormalAndroidResultPublicationMatchesTrustedBytes` and negative `c18CrossPidParentSwapMustNotExposeForgedResultAfterFailedPublish`. The native writer's existing `atomicReplace` test seam triggers the deterministic cross-process replacement; the negative retains the strict **no forged result visible** assertion, not merely an IOException. Do not claim PASS until exact-head JUnit/logcat confirms it; expected RED is a verified blocker, not a release regression to skip.
- Scope: synthetic app-private cache files only, no real PDF/ledger/SQLite/LKG. The same-UID arbitrary-writer model can fabricate bytes at a pathname without invoking the writer, so absence of hostile content cannot be guaranteed by a post-move readback or pathname cleanup. Full closure requires a trusted publication/consumer authority and directory/inode custody, with Android-supported semantics proven independently. C13 arbitrary writable FD, durable fsync recovery, 87K-page global negative proof and real-phone validation remain HOLD. PR OPEN/DRAFT/Merge HOLD, no Owner APK or auto-post.


### 2026-10-29 C19 API35 FD-anchored publication primitive witness — pending exact-head CI
- FIRST FRESH READ: PR OPEN/DRAFT HEAD `a79e871b1916e2cdc945cfdd84012f8dd7b0f107`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`, Issue #13 OPEN. Exact-head CI #40792729613 completed FAILURE: Native JVM C17 `failedPublicationMustNotLeaveForgedResultVisible` and Android API35 C18 `c18CrossPidParentSwapMustNotExposeForgedResultAfterFailedPublish`; original Android job log independently confirms `C18_ANDROID_CROSS_PID_FORGED_RESULT_VISIBLE_AFTER_FAILED_PUBLICATION`. True workflow_dispatch Signed #40792738650 failed CI-authority validation; no release authority.
- Add one Android API35 real-independent-PID positive/negative `c19SecureDirectoryStreamMoveAnchorsOriginalParentAcrossCrossPidSwap` using Java API26+ `SecureDirectoryStream.move` and the existing restricted debug-only cross-PID parent/temp swap. Assert original held parent receives TRUSTED bytes, replaced public parent receives no writer publication, and adversarial new-parent temp remains separate. Preserve both C17/C18 strict RED tests unchanged; **no production Kotlin change** and no claim of publication/consumer safety or Android physical-device proof.
- If Android API35 SecureDirectoryStream is unavailable or move fails, keep the original CI first error and fail closed; do not fallback to pathname `Files.move`. Next gate is source-bound secure temporary inode custody + anchored publish + durable receipt/consumer authority, with C17/C18 still blocking until their actual security invariants are resolved. Same-UID arbitrary pathname writes cannot be prevented solely by anchoring writer move. Native Gate B, ~87K-page global negative proof, Signed >=4.20.37+495, Owner APK and merge remain HOLD. No ledger/SQLite/NT$700/official PDF/LKG/main mutation.


### 2026-10-29 C20 anchored default publication candidate — source/test submitted, CI pending
- Source authority: C19 exact-head `4c4f7594b2d2ebe61be9b4cfd4a9d4d55f97f7f4` Android API35 Emulator JUnit artifact `12865493059`, ZIP SHA256 `e56d757900aecb68c5f3b140ba51736a512ce9240a48c67f5d585b17d69f88b6`, CRC PASS, 7 tests / 6 PASS / 1 FAIL (the pre-existing C18 strict RED). C19 `c19SecureDirectoryStreamMoveAnchorsOriginalParentAcrossCrossPidSwap` independently PASS with a different PID/same UID; original held parent receives trusted bytes and replaced pathname receives no writer publication. This is Android Emulator, not a physical phone.
- C20 modifies only the **default** `PlatformResultAtomicWriter.write` path: one `SecureDirectoryStream` opened before temporary creation; unique relative CREATE_NEW/NOFOLLOW channel, FileChannel.force(true), and same-held-directory `move`. Unsupported directory stream or unsyncable temporary channel fails closed, never falls back to pathname `Files.move`. Existing injected `atomicReplace` fault seams remain for strict C17/C18 RED witnesses. Add JVM normal and deterministic parent/temp replacement regressions for the default anchored path.
- Scope is **writer-caused parent/temp pathname redirection only**. A hostile same-UID process can still independently place a forged result at the public consumer pathname, and `verifyPublishedBytes`/`syncParent` remain pathname based; no durable receipt or trusted consumer authority exists. Therefore C17/C18 P0 RED, C13 arbitrary writable FD, same-UID threat boundary, crash/fsync recovery, global ~87K negative completeness, Owner Signed >=4.20.37+495 and Merge remain HOLD. Do not weaken/skip C17/C18 or claim overall CI GREEN. No main/ledger/SQLite/POSTED NT$700/official PDF/LKG writes.


### 2026-10-29 C21 Android API35 default production publisher independent-PID test (exact-head CI pending)
- FIRST FRESH READ PR OPEN/DRAFT HEAD `284129956f30fff892d0fb0a15e3722e52ddcbd8`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version 4.20.36+494, Issue #13 OPEN. Exact-head CI #40801016353 complete FAILURE: original native JVM job log 574022 characters, 69 tests/1 failed at C17 `failedPublicationMustNotLeaveForgedResultVisible` line 191; API35 emulator original job log 128356 characters, 7 tests/1 failed at C18 `c18CrossPidParentSwapMustNotExposeForgedResultAfterFailedPublish` line 262. Both RED assertions remain unchanged.
- C21 adds `c21DefaultProductionWriterAnchorsPublicationAcrossCrossPidSwap` to real API35 instrumentation. It invokes the actual default C20 production writer while a separate same-UID Android PID swaps parent and temporary pathname at the existing test seam. Assertions: trusted bytes in held original directory, no writer promotion of the hostile replacement-directory temp, and public-path readback fail-closed. This is a bounded writer-side custody regression, NOT full consumer authority or durable recovery.
- Await exact-head CI/JUnit before claiming C21 PASS. C17/C18, arbitrary same-UID forged consumer pathname, C13 hostile FD, fsync crash recovery, ~87K-page negative completeness, Android physical phone and Signed >=4.20.37+495 all HOLD. PR OPEN/DRAFT/Merge HOLD, no main/ledger/SQLite/POSTED NT$700/official PDF/LKG mutation, no auto-post.

### 2026-10-29 C21A API35 Debug Probe strict-scope repair (source committed; CI pending)
```text
Debug-only PlatformLeaseProbeService.SWAP_C12_PARENT
  ├── allowed immediate cache roots: pr45-c12-<UUID> OR pr45-c21-<UUID>
  ├── required temp: .result.json.*.tmp, existing regular NOFOLLOW
  ├── unrelated cache parent → IOException / no mutation (new API35 negative)
  ├── separate PID / same app UID / SELinux evidence retained
  └── production C20 default writer → C21 real Android positive (must rerun)
Production PlatformResultAtomicWriter / ResultProcessLease / SourceSnapshotCustody
  └── UNCHANGED; C17/C18 consumer-visible forged-result RED still blocks Gate B
Storage / ledger / SQLite / official PDF / LKG: UNCHANGED
```
Exact prior head `0ae69100e20214e0380101c138310f19f4f2535f` CI [#40802574173](https://github.com/easonliu714/my_finance_app_public/actions/runs/40802574173) FAILED with C21 debug scope IOException, C17/C18 RED; next exact-head CI required. No Signed/Owner APK authority, no release bump, no merge. Consumer receipt/durable recovery, hostile same-UID FD, real-device and global 87K negative proof HOLD.


### 2026-10-29 C22 fail-closed bounded-search terminal completeness (adjacent Gate; exact-head CI required)
- Preflight: PR OPEN/DRAFT HEAD `a126746aef7cbdd705babba3350538a778e8f42f`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`, Issue #13 OPEN. Exact-head CI [#40805877000](https://github.com/easonliu714/my_finance_app_public/actions/runs/40805877000) FAILED: native JVM 69/1 C17 line 191; Android API35 9/1 C18 line 262; true Signed #40805885083 FAILED CI authority, no release.
- C17/C18 original strict assertion requires that an arbitrary same-UID hostile process **cannot leave its own bytes visible at a public writable pathname**. Counterexample: after any writer return, the adversary writes a new file at that pathname. Writer-only fixes cannot prevent this. `SPEC_UNSATISFIABLE_OR_OWNER_THREAT_MODEL_DECISION_REQUIRED`: Owner must choose separate security domain/UID and trusted consumer channel, or redefine acceptance as "untrusted bytes may be visible but never accepted as authoritative". Do not weaken C17/C18 tests without explicit decision; retain both RED.
- Adjacent C22 source change: both native bounded-search workers must publish COMPLETE **only** if every exact candidate has an in-range page-backed positive; partial/zero/foreign/invalid-page evidence fails closed with `PLATFORM_WORKER_NEGATIVE_COVERAGE_UNPROVEN` or `PDFIUM_WORKER_NEGATIVE_COVERAGE_UNPROVEN`. Synthetic Kotlin positive/negative tests cover full, partial, zero, foreign, duplicate, missing and out-of-range pages. No assertion that 87K pages are globally monotonic; a global negative still requires complete official-source proof and remains UNKNOWN.
- This does not authenticate a same-UID forged terminal file, establish durable fsync recovery, or close C12/C13. Android API35 independent PID, real phone, version >=4.20.37+495, exact-head CI/Signed and Owner UAT remain HOLD. PR OPEN/DRAFT/Merge HOLD; main, ledger/SQLite/NT$700 POSTED, 135200798-byte official PDF/LKG and auto-post remain frozen.


### 2026-10-29 C23 PDFium native publisher integration (exact-head CI required)
```text
PdfiumCandidateWorkerService
 ├─ RUNNING / COMPLETE / FAILED: same Android PID + per-process UUID epoch
 ├─ COMPLETE: source_sha256 + candidate_universe_sha256 required
 └─ writeAtomic → PlatformPdfiumResultPublisher
      └─ PlatformResultAtomicWriter (strict epoch/provenance, C20 anchored move)
           ├─ unique CREATE_NEW/NOFOLLOW temp + file fsync
           ├─ no renameTo / direct target.writeText fallback
           └─ terminal immutability / fail-closed on rename error
Robolectric API35: 4 positive/negative cases (CI pending)
C17/C18 hostile same-UID consumer-visible forged pathname: strict RED/HOLD
C13 arbitrary writable FD / durable fsync / 87K global negative: HOLD
SQLite / ledger / POSTED NT$700 / official PDF-LKG: FROZEN
```
PR OPEN/DRAFT/Merge HOLD, version 4.20.36+494; no Signed/Owner APK. Previous exact-head CI #40811726404: C17/C18 RED, true Signed #40811734103 FAILED. C23 is a bounded PDFium writer fix, not trusted consumer authority.


### 2026-10-29 C24 PDFium source inode custody — source/test submitted, exact-head CI required
- Fresh PR OPEN/DRAFT pre-HEAD `48e19bcc8fe6f6204ad51803caeeb9f9d8dc99b2`; main remains `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`; version `4.20.36+494`. Exact-head Flutter CI #40816790468 FAILED only strict C17 native JVM (69/1, line 191) and C18 Android API35 (9/1, line 262); Signed #40816797529 FAILED CI authority, no release APK. C23 PDFium publisher regressions were not first failures.
- C24 removes PDFium's separate `sha256File(source)` followed by `ParcelFileDescriptor.open(source)` pathname reopen. PDFium now consumes the SHA-verified unlinked private snapshot FD returned by `PlatformSourceSnapshotCustody`, and terminal `source_bytes` comes from that verified snapshot, not mutable `source.length()`. The descriptor is closed on failed open and transferred to PDFium only on successful `newDocument`. Add two Robolectric API35 source identity/mismatch tests.
- This closes a bounded PDFium source pathname-swap TOCTOU, NOT same-UID hostile post-return writable FD, trusted Consumer acceptance, C17/C18 arbitrary public pathname visibility, fsync crash recovery or ~87K global-negative completeness. Strict C17/C18 RED remain unchanged and `SPEC_UNSATISFIABLE_OR_OWNER_THREAT_MODEL_DECISION_REQUIRED` / `SECURITY_GATE_NOT_CONVERGING` remain. PR OPEN/DRAFT/Merge HOLD; no main, ledger/SQLite/POSTED NT$700/official PDF/LKG mutation, no auto-post; no Owner APK.


### 2026-10-29 C24A first-failure repair — Kotlin nullable FD and Flutter source custody contract (CI pending)
- Fresh PR #45 OPEN/DRAFT HEAD before `36311351ec2711cab1d666e4d3d70e16cdef7735`; main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, app version `4.20.36+494`, Issue #13 OPEN. Exact-head Flutter Android CI [#40822357478](https://github.com/easonliu714/my_finance_app_public/actions/runs/40822357478) FAILED for two **new C24 regressions**: Android `compileDebugKotlin` at `PdfiumCandidateWorkerService.kt:243:45` requires non-null `ParcelFileDescriptor` for `pdfiumCore.newDocument`; Flutter full suite 2053 PASS / 1 FAIL at `invoice_award_cloud_pdf_memory_policy_contract_test.dart`, which still asserted the old worker-local `ParcelFileDescriptor.MODE_READ_ONLY` after C24 moved FD opening to `PlatformSourceSnapshotCustody`. Exact-head true Signed [#40822364103](https://github.com/easonliu714/my_finance_app_public/actions/runs/40822364103) FAILED CI authority; no APK release.
- C24A source repair supplies explicit non-null FD at `newDocument`, retains ownership in nullable holder until PDFium successfully accepts it, and closes on error. Flutter contract now asserts READ_ONLY/unlink at the authoritative snapshot custody location and prohibits the worker from reopening/hash-checking the caller-controlled pathname. Existing C24 Robolectric positive/negative tests and strict C17/C18 RED remain unchanged. New exact-head CI/JUnit required; no local Android SDK/runtime claim.
- SECURITY_GATE_NOT_CONVERGING: C17/C18 arbitrary same-UID public-path forgery remains P0 RED, `SPEC_UNSATISFIABLE_OR_OWNER_THREAT_MODEL_DECISION_REQUIRED`; no unilateral weakening. C13 hostile FD, trusted consumer receipt, fsync crash recovery, global ~87K-page negative completeness and Signed >=4.20.37+495 remain HOLD. No main/ledger/SQLite/POSTED NT$700/official PDF-LKG mutation, no auto-post, no Owner APK or merge.


### 2026-10-29 C24B exact-head CI contract repair (pending new CI)
- Previous exact HEAD `1c143d812d28a3ea7b9dc236095269f4f4a3c7ba`: Flutter Android CI [#40828308773](https://github.com/easonliu714/my_finance_app_public/actions/runs/40828308773) FAILED. Flutter full suite 2053 PASS / 1 FAIL: stale contract expected literal `pdfiumCore.newDocument(descriptor)`, but C24A correctly requires non-null checked `descriptor ?: throw IOException("PDFIUM_SOURCE_DESCRIPTOR_MISSING")`. Android API35 independent-PID instrumentation 9 tests / 1 FAIL, strict C18 at line 262. True Signed [#40828317119](https://github.com/easonliu714/my_finance_app_public/actions/runs/40828317119) FAILED CI authority, no Signed APK.
- C24B updates the source-level Flutter contract to assert guarded verified FD handoff, explicit missing-descriptor failure and ownership transfer only after successful `newDocument`. Preserve strict C17/C18 unchanged; no security regression assertion removed. This is CI contract repair, **not** C17/C18 P0 closure.
- `SECURITY_GATE_NOT_CONVERGING` / `SPEC_UNSATISFIABLE_OR_OWNER_THREAT_MODEL_DECISION_REQUIRED`: arbitrary same-UID writes to a public pathname make forged-file invisibility impossible without a protected trust boundary. Do not weaken C17/C18 without Owner authorization. Consumer authority, C13 hostile FD, fsync recovery, ~87K global negative proof, Signed >=4.20.37+495, device UAT and Merge remain HOLD. No main, ledger, SQLite, POSTED NT$700 or official PDF/LKG writes; no auto-post.


### 2026-10-29 C25 PDFium single-owner/OS lease parity (exact-head CI required)
- Fresh before HEAD `41653bf154c7d576b527adbf881df3c131b72778`, PR OPEN/DRAFT, main frozen. CI #40834889683 FAILED: strict C17 native JVM 69/1 line 191 and C18 Android API35 9/1 line 262; Signed #40834897756 FAILED. No authorized APK.
- PDFium onStartCommand previously launched foreground and thread on every start without PlatformWorkerStartLease. C25 reuses the kernel-fenced result lease before foreground/thread, rejects overlaps without FAILED or tearing down the owner, and releases only after foreground cleanup. Adds synthetic JVM positive/negative two-instance ownership test; Android independent-PID verification remains required.
- C17/C18 RED untouched. SECURITY_GATE_NOT_CONVERGING / SPEC_UNSATISFIABLE_OR_OWNER_THREAT_MODEL_DECISION_REQUIRED: arbitrary same-UID public-path forgery cannot be made invisible by a Writer-only change. Consumer authority, hostile FD, fsync recovery, 87K global negative proof, Signed >=4.20.37+495, device UAT and Merge HOLD. Main, ledger, SQLite, POSTED NT$700, official PDF/LKG and auto-post frozen.


### 2026-10-29 C26 sampled cross-page monotonicity fail-closed regression — exact-head CI required
- Pre-head `36fd462ebecdd501fb2eb9f1975fa63948449a0d`, PR #45 OPEN/DRAFT, main frozen, version 4.20.36+494. Exact-head C25 Flutter Android CI #40840539490 FAILED: native JVM 70 tests/1 strict C17 (PlatformResultAtomicWriterTest.failedPublicationMustNotLeaveForgedResultVisible); Android API35 strict C18 (PlatformResultProcessLeaseInstrumentedTest.kt:262). Genuine Signed #40840548119 FAILED CI authority, no APK.
- Both Platform PdfRenderer and PDFium bounded candidate workers now use a shared ordered-page observation gate. Sampled pages must have sorted nonempty tokens, valid page indices, and non-inverting first/last bounds relative to all previously observed lower/higher page indices. An observed inversion throws before COMPLETE; the existing failure handler retains UNKNOWN. Five deterministic JVM positive/negative tests cover 87K-index distant inversion, middle insertion, changed bounds, invalid/unsorted pages and equal boundary. Local standalone Kotlin smoke PASS only; full exact-head CI/Android proof pending.
- LIMIT: this checks **observed** pages only, NOT all 87K pages; it cannot prove a global negative or authenticate result pathname. C17/C18 strict RED remain untouched; SECURITY_GATE_NOT_CONVERGING and SPEC_UNSATISFIABLE_OR_OWNER_THREAT_MODEL_DECISION_REQUIRED. Owner must choose a protected trust boundary versus consumer-only nonacceptance, without unilateral weakening of tests. C13 hostile FD, fsync recovery, full negative proof, Signed >=4.20.37+495, Owner UAT and merge HOLD. No ledger/SQLite/POSTED NT$700/official PDF/LKG writes or auto-post.

### 2026-10-29 C27 repeated-page token stability — bounded native safety repair
- Fresh pre-head `b344a554af9518e001515bf5285f4fca15a1b0b9`, PR #45 OPEN/DRAFT, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`. Exact-head C26 Flutter Android CI [#40849124912](https://github.com/easonliu714/my_finance_app_public/actions/runs/40849124912) FAILED: native JVM 70 tests / 1 strict C17 at PlatformResultAtomicWriterTest.kt:191; Android API35 independent PID 9 tests / 1 strict C18 at PlatformResultProcessLeaseInstrumentedTest.kt:262. True Signed workflow_dispatch [#40849135376](https://github.com/easonliu714/my_finance_app_public/actions/runs/40849135376) FAILED CI authority; Android evidence artifact 12885794531 is not Signed APK.
- C27 repairs the shared `PlatformObservedPageOrderGate.observe` invariant: PDFium re-reads may yield identical first/last page bounds but different interior invoice tokens. Store a defensive full ordered-token snapshot for each observed page, reject changed interior tokens or count on revisit, and preserve all cross-page bounds checks. Two JVM synthetic positive/negative regressions cover identical bounds with changed middle token/count and caller-owned mutable list mutation. Local standalone Kotlin smoke 6/6 PASS; repository native JVM/Android CI is still required and cannot be inferred from local smoke.
- C27 is a bounded consistency fix, **not** a global 87K-page negative-completeness proof; unvisited pages remain UNKNOWN. C17/C18 public-path forged-file visibility is unchanged and strict RED must remain. `SECURITY_GATE_NOT_CONVERGING` and `SPEC_UNSATISFIABLE_OR_OWNER_THREAT_MODEL_DECISION_REQUIRED`: if an arbitrary same-UID adversary can create public-path files, Writer-only nonvisibility is impossible. A protected independent trust domain or explicit consumer-nonacceptance threat-model decision is needed; no unilateral test weakening. C13 hostile FD, trusted consumer receipt, fsync recovery, release >=4.20.37+495, Owner APK and merge HOLD. Main, ledger/SQLite/POSTED NT$700, official 135200798B PDF/LKG and auto-post frozen.


### 2026-10-29 C28 source-order preservation in both native PDF engines (pending exact-head CI)
- Fresh preflight PR #45 OPEN/DRAFT, branch HEAD `871aa37537ca610f9f93d436c84f2b6bfa5f02bf`, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`, Issue #13 OPEN. Exact-head C27 CI [#40856989416](https://github.com/easonliu714/my_finance_app_public/actions/runs/40856989416) FAILED: native JVM 70/1 strict C17 at `PlatformResultAtomicWriterTest.kt:191`, Android API35 9/1 strict C18 at `PlatformResultProcessLeaseInstrumentedTest.kt:262`. True Signed #40857008949 FAILED CI authority; no Signed APK.
- C28 found a source-level contradiction in C26/C27: both native PDF workers' `extractInvoiceNumbers` used `.distinct().sorted()` before passing tokens to `PlatformObservedPageOrderGate.observe`, so an out-of-order extracted page was silently sorted and could falsely pass observed-page monotonicity. Both workers now delegate to `PlatformInvoicePageTokenExtractor.extractInDocumentOrder`, preserving source order and duplicates while retaining original canonical regex and boundary checks. C26/C27 observed-page gate rejects inverted pages and detects repeated-page row drift.
- Five native JVM positive/negative regressions: ordered page accepted; inverted source order rejected; duplicate row identity preserved; whitespace/case normalization stable; embedded alphanumeric false positives rejected. Standalone Kotlin smoke 5/5 PASS only, not repository CI or Android runtime. Require exact-head GitHub native JVM/Android CI; never claim global negative proof.
- C17/C18 original strict RED tests remain untouched. `SECURITY_GATE_NOT_CONVERGING` and `SPEC_UNSATISFIABLE_OR_OWNER_THREAT_MODEL_DECISION_REQUIRED`: arbitrary same-UID attacker writing a public pathname makes forged-file invisibility impossible via Writer alone. Do not loosen tests; Owner must select protected trust domain or explicitly authorize consumer-only nonacceptance. C13 hostile FD, trusted consumer receipt, crash/fsync recovery, 87K unvisited-page negative completeness, Signed >=4.20.37+495, Owner device UAT and merge HOLD. No main, ledger, SQLite, POSTED NT$700, official 135200798B PDF/LKG mutation; no auto-post.

## C29 — 2026-10-29 19:51 Asia/Taipei · Canonical candidate universe fail-closed

- Fresh parent `f59defcf91debbbfa2d8cc5ea4d9b42c9d947ac5`, PR #45 OPEN/DRAFT, main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`, version `4.20.36+494`. Exact-parent Flutter Android CI [#40864615153](https://github.com/easonliu714/my_finance_app_public/actions/runs/40864615153) FAILED: JVM 70/1 strict C17 line 191; Android API35 9/1 strict C18 line 262. True Signed workflow_dispatch [#40864625822](https://github.com/easonliu714/my_finance_app_public/actions/runs/40864625822) FAILED CI authority; Android evidence artifact 12892479492 is NOT a Signed APK.
- C29 Production `PlatformCandidateCompletionGate.allCandidatesPositivelyMatched` now refuses malformed, lowercase, spaced or length-invalid invoice candidate identities even if a forged/malformed result supplies internally consistent page-backed matches. One native JVM test covers single and mixed invalid universes; this is an adjacent fail-closed schema fix, not global 87K negative completeness or result authenticity. Exact new-HEAD CI required; local smoke is not Android evidence.
- Original strict C17/C18 tests unchanged and RED: `SECURITY_GATE_NOT_CONVERGING` / `SPEC_UNSATISFIABLE_OR_OWNER_THREAT_MODEL_DECISION_REQUIRED`. Arbitrary same-UID public pathname write defeats a Writer-only guarantee that forged files never become visible. Owner must choose protected independent UID publication or authorize consumer-only nonacceptance; do not silently change assertions. No main, formal ledger/SQLite, POSTED NT$700, official 135200798B PDF/LKG mutation; no auto-post, merge or Owner APK. Native Gate B remains HOLD.
