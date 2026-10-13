# 記帳軟體 UI／功能／外部 API／SQLite 資料架構樹與完成驗證矩陣

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
