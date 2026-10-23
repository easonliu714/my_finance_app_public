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
