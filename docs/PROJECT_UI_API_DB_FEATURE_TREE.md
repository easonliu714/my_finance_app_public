# 記帳軟體 UI／功能／外部 API／SQLite 資料架構樹與完成驗證矩陣

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
