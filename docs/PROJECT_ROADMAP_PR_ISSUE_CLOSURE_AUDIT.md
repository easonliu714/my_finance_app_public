# 記帳軟體 Roadmap／PR／Issues 結案稽核與防重工治理

> **CURRENT 2026-10-14 10:57:** 4.20.33 screen-off survival Owner PASS, >5–8min candidate completion HOLD. New 4.20.34 phase-specific native PDF stage visibility SOURCE ONLY/CI PENDING; no SHA bypass. Latest append below supersedes older NEXT labels.

> **CURRENT 2026-10-14 09:07:** 4.20.32 Group UX Owner PASS & exact CI/Signed PASS. New cloud-500 worker screen-off regression OWNER FAIL; 4.20.33 worker mitigation CODE ONLY/CI PENDING. Other cloud tiers candidate direct lookup gated next. See latest appendix; older NEXT/CURRENT headers are historical.

> **CURRENT GATE 2026-10-14:** 4.20.31+489 backup/restore OWNER PASS and exact CI/Signed PASS; 4.20.32+490 Issue #4 existing group balance caption semantics CODE only. See latest appendix at document end; old NEXT CANDIDATE/CI labels below are historical.

## NEXT CANDIDATE AUTHORITY — 4.20.30+488 Issue #4 年度摘要可讀性（2026-10-13）

- Following frozen `4.20.29+487` (accepted code HEAD `375ef1078dd6c21f8d1683260d8c497498362011`, Flutter CI `38402561190` SUCCESS, Signed Canary `38402572785` SUCCESS, Owner 2026-10-13 22:03–22:04 device PASS), a new **separately versioned** 4.20.30+488 branch candidate is now CODE COMMITTED; that .29 owner acceptance does not transfer automatically.
- `lib/features/account/account_detail_page.dart` / `_CompactPeriodSummaryCard`: split period label from numeric net onto independent lines with `FittedBox(BoxFit.scaleDown)`, replacing same-line `Row` that caused iPASS Money year's title `20...`; pinned summary header extends to `MediaQuery.textScalerOf(context).scale(172.0)` to retain full title at text scaling. No change to `summaryFor`, account/transaction balances, ledger, SQLite, currency conversions, or official award process.
- Version contracts rotated to `4.20.30+488`, AppBuildMetadata phase `issue-13-accepted-issue-4-summary-title-488` (retains required `issue-13-` Signed Canary policy prefix), with 4 release exact identity tests and LAB validationVersion matching. `test/issue_4_issue_13_4_20_28_ux_contract_test.dart` adds layout-source regression asserting that full period label does not share a constrained same-line Row with a large numeric balance; source contract complements but does **not replace** actual Flutter Widget/device geometry proof.
- New successor gates: Flutter Analyze FULL SUITE + Debug APK, true workflow_dispatch Signed Canary Validated BuildInspect, independent artifact SHA/signer/version and owner 360px e-wallet full `2026年` label screenshot. Only these fresh exact-head results can mark `4.20.30` READY. PR #45 remains OPEN/DRAFT/MERGE HOLD, Issue #4 still OPEN because type-group collapsible UX & liability/multi-currency semantics remain unfinished.
- Next *following* step after title's real-device PASS is Issue #4 account list grouping type fold/semantic audit; source inspection/DoD first, no secondary balance calculation, no destructive schema. Issue #13 official draw scheduling baseline discrepancy (`16:00` issue text vs `14:00` current UI) requires owner/authority reconciliation, not silent runtime modification.

## CURRENT AUTHORITY — 4.20.29 OWNER PASS（2026-10-13 22:08 Asia/Taipei）

> **本節優先於下方的歷史 Gate 快照。** Code/head 的 immutability authority 是 4.20.29+487 `375ef1078dd6c21f8d1683260d8c497498362011`，不是文件後續 commit SHA。任一新的 source/doc commit 均需重新查該新 HEAD 的 CI；不能將舊執行結果假裝成新 HEAD 成果。

### 正式驗收證據與限制

| Gate | Status | authority |
|---|---|---|
| 4.20.29 Flutter Analyze / Full tests / Debug APK | PASS | [CI run 38402561190](https://github.com/easonliu714/my_finance_app_public/actions/runs/38402561190) on `375ef1078dd6c21f8d1683260d8c497498362011` |
| True workflow_dispatch Signed Canary Validate + BuildInspect | PASS | [run 38402572785](https://github.com/easonliu714/my_finance_app_public/actions/runs/38402572785), artifact 11816709394, GitHub digest `sha256:8b986df3b780add48effda86d38a5b5537f8aaeb805634dd7873f46daa0c7860` |
| Owner Issue #13 期別短標籤/期限下置/問號外置 | DEVICE=PASS | 2026-10-13 22:03 owner screenshot, [Issue #13 acceptance](https://github.com/easonliu714/my_finance_app_public/issues/13#issuecomment-6147521076) |
| Owner Issue #4 銀行、一卡通 Money 明細精簡及定位 | DEVICE=PASS (observed slice) | 2026-10-13 22:03~22:04 owner screenshot, [Issue #4 acceptance](https://github.com/easonliu714/my_finance_app_public/issues/4#issuecomment-6147519708) |
| GitHub PR | OPEN/DRAFT/Merge HOLD | PR #45 only; #46 already CLOSED_NOT_MERGED |
| Pure Open Issues | 18 | None automatically CLOSED without complete per-issue DoD |

**畫面核對：** iPASS Money 在 2026/05、08 月的月卡分別顯示 -1.87K 與 -2.37K TWD，年度合計 -6.42K TWD；銀行帳戶 balance 700 TWD，year 2026 700，month 10 200，兩筆已 POSTED +500/+200 仍為總 700。不能由截圖推定 live bank API 回傳、全 SQLite readback、所有帳戶類型／跨年極端案例通過。Owner 宣告本輪合併 Gate PASS 予以記錄，未獨立取證的原 Issue 細項仍 OPEN。

**尚存小 UI 缺口（下一版處理，不否定 4.20.29 Owner PASS）：** iPASS Money 年度標題截成 `20...`，與指定 `2026年` 不符。原始碼 `_CompactPeriodSummaryCard` 將年標籤與 `-6.42K TWD` 金額塞在同一水平 Row；下一個最小 UI successor 需使年度標籤完整顯示、金額保持可讀，並新增狹窄裝置/較大字型回歸測試，不能篡改帳務數字。

### 下一階段 Roadmap（優先順序／範圍控制）

```text
P0 [ACCEPTED_FROZEN] 4.20.29+487 owner combined Gate + exact-head signed artifact
    ├── Issue #13 period-only dropdown + help icon exterior + deadline below
    └── Issue #4 compact ledger + month-following account summary (observed bank/e-wallet)
P1 [NEXT] Issue #4 shared yearly tile full-title layout (2026年, no 20...)
    ├── SOURCE: lib/features/account/account_detail_page.dart / _CompactPeriodSummaryCard
    ├── TEST: narrow 360px, longer amounts, large accessibility text, no overflow
    ├── Invariant: account balance/period net/POSTED untouched
    └── Gate: new exact-head analyze/full suite/signing and owner-focused device
P2 [PLANNED] Issue #4 account list type-group collapse and group summary semantics
    ├── Read existing account list/selector widgets before any new component
    ├── Credit/loan/investment liabilities, currency separation; no invented netting
    └── Define and verify no-mutating grouping contract before app UI implementation
P3 [HOLD_ORIGINAL_DOD] Issue #13 external timing/reconciliation + Issue #4 remaining gaps
    ├── Issue #13 describes approx 16:00 odd-month 25th, UI current scheduler shows 14:00
    │   → explicit owner/authority reconciliation, do not silently change schedule
    ├── External settlement/official remittance/manual confirmed credit proof distinct
    └── Multi-account/year rollover tests, physical schema checks as separately scoped
```

**防重複實作**：PR #46 已 CLOSED_UNMERGED；Issue #4 摘要/渲染使用同一 `AccountDetailPage`，不得做第二套 period/balance 計算；Issue #13 保留獎號同步唯一 runtime，正式記帳只能獨立用戶同意，既有 NT$500+NT$200=700 POSTED 不重複、不背景補登。**兩份 docs 每個實際進度節點一起更新；不可把文件提交等同 main 已 MERGED。**

---

> 更新：2026-10-13 16:55 Asia/Taipei。Repo `easonliu714/my_finance_app_public`，PR #45 active HEAD `43dfc02f5b78fa1900c7d83ba7b57d0b8888f5b2`。本次原始碼全文基準為使用者上傳的 **舊 HEAD `dec1c2d994143fe358058f11a38206e47bcac454` ZIP**；最新 4.20.28 五檔差異以 GitHub readback 為據，未將舊 ZIP 誤寫成最新 checkout。
> 狀態：`CODE` 原始碼存在，`TEST` 自動測試通過，`DEVICE` 實機通過，`HOLD` 未達 Gate，`CANDIDATE` 已 commit 但未驗證，`PLANNED` 缺實作。CODE != TEST != DEVICE != MERGED。

## 0. 權威、數量及不能跨越的界線

- GitHub current PR #45 `OPEN/DRAFT`，HEAD `43dfc02f5b78fa1900c7d83ba7b57d0b8888f5b2`；base main `a8f1ad67671b93d9bbe52d5cf7599e2f308474b8`。
- Open PR **2**：#45、#46；Closed PR **23**，其中合併與直接 Close 需分開判斷。
- Open 純 Issues **18**：API 取得 20 筆 open issues 其中 2 筆是 PR，不能算成 open issue。Closed 純 Issues **3**：#20、#29、#32；其餘 closed items 是 PR。
- 新 HEAD 的 Flutter Android CI Run `38356246784` **FAIL at Run tests**，Signed Canary Run `38356252713` **FAIL** at wait-exact-head CI，Build/Inspect SKIPPED。修復詳細根因需讀失敗測試輸出；**目前不得 READY**。
- 4.20.28+486 的 5 個人工網頁提交已通過檔案 SHA / changed paths，比對通過不等於 CI 通過。
- 本文沒有關閉任何 Issue/PR，沒有對 DB/外部 API 進行操作，也沒有更改正式帳本。

## 1. Roadmap 多階層 Gate Tree

```text
my_finance_app_public — 台灣個人記帳（五分頁：帳戶／計畫／首頁／報表／我的）
├─ R0 Local-first 正式帳本與資料安全 [CODE；已完成若干 owner device Gate]
│  ├─ Transaction canonical record + explicit save/transfer [CODE／歷史 Gate]
│  ├─ SQLite canonical production schema v24 [CODE；未於本輪 live DB PRAGMA 重驗]
│  ├─ 備份/還原/可讀匯出/隱私隔離 [CODE；round-trip 全版驗收待查]
│  └─ 終局 schema freeze → encryption [OPEN #18；NOT IMPLEMENTED]
├─ R1 帳戶與資金週期 [ACTIVE #4 #5 #6 #7 #9]
│  ├─ 4.20.28: 卡片精簡、真實 visible anchor、年/月同步 [COMMITTED；CI FAIL]
│  ├─ 帳戶型別群組／負債／多幣別語意 [PARTIAL；#4 不能整張 close]
│  ├─ 簽帳卡 reserve/settlement [PARTIAL；#6]
│  ├─ 儲值 profile／suggestion／execution [CODE；#9 完整 device Gate 未證]
│  └─ 貸款提前償還 simulation [OPEN #7]
├─ R2 記帳輸入效率 [ACTIVE #5 #10 #11 #14]
│  ├─ 手動帳戶/商家/類別選單與輸入 [CODE]
│  ├─ quick-add、常用收藏、時間建議 [OPEN]
│  └─ 首頁 shortcut local customization [OPEN #14，獨立於 4.20.28]
├─ R3 發票／商家／雲端／圖片／AI [ACTIVE #13 #16 #17 #22]
│  ├─ 官方商業登記／商家 identity V24 [CODE；#20 已 CLOSED]
│  ├─ OCR→Frozen Review→正式交易明確 Save [CODE／歷史 Gate]
│  ├─ Cloud Invoice Inbox / CSV / lab adapters [CODE；lab 不等於 production]
│  ├─ #13 官方一般獎+雲端四 tier、候選與 POSTED [4.20.26 owner 核心 PASS]
│  │  ├─ #45 active 4.20.28 『？』說明精簡 [COMMITTED；CI FAIL]
│  │  ├─ #46 older auto-refresh runtime [OPEN DRAFT；先 crosswalk 避免重複 merge]
│  │  └─ 外部銀行入帳獨立驗證／完整帳務對帳 [NOT PROVEN]
│  ├─ #16 商品照片 Gemini review-first [已有歷史 PR，整體 DoD 未逐項驗證]
│  ├─ #17 crop/retention [OPEN]
│  └─ #22 OCR 自動 Gemini opt-in [已有歷史 PR，實機完整 DoD 未證]
├─ R4 語音與設定 [ACTIVE #8 #12 #19 #28]
│  ├─ 語音→逐字稿→draft→explicit Save [CODE，#28 overall open]
│  ├─ 全域 notifications、統一設定中心／quota [OPEN]
│  └─ 2027 官方工作日更新、CSV 安全 fallback [OPEN #19]
├─ R5 CI/PR 正式治理 [ACTIVE #15]
│  ├─ exact HEAD → Flutter analyze/full tests/build [4.20.28 FAIL]
│  ├─ Signed Canary → APK SHA/signature/permissions [4.20.28 BLOCK]
│  ├─ Owner real-device UX [4.20.28 NOT STARTED]
│  └─ PR #45/#46 Draft → separately authorized merge [HOLD]
└─ R6 歷史版與閉環清理
   ├─ PR #1-#44 逐一按 merged_at/closed_at/DoD 標示，不以 closed 推定 merge
   ├─ Open #4 #13 #16 #22 等 partial scopes 細分子 Gate
   └─ 禁止新建重複 CRUD／invoice parser／wallet top-up／merchant registry
```

## 2. Open PR（完整）

| PR | 現況 | 建議 | Close 條件 |
|---|---|---|---|
| [#45](https://github.com/easonliu714/my_finance_app_public/pull/45) | Issue #13 官方發票資料與 4.20.28 發票/帳戶 UX；OPEN DRAFT，CI FAIL | **KEEP** | 不能因另張 PR 已具相似功能就直接 close；先按 changed-path/blob、main ancestry、測試和來源權威逐項判斷 |
| [#46](https://github.com/easonliu714/my_finance_app_public/pull/46) | Issue #13 自動獎號同步獨立 PR；OPEN DRAFT，需比對 #45 的實際重疊與落點 | **KEEP** | 不能因另張 PR 已具相似功能就直接 close；先按 changed-path/blob、main ancestry、測試和來源權威逐項判斷 |

歷史 closed PR：#1, #2, #3, #21, #23, #24, #25, #26, #27, #30, #31, #33, #34, #35, #36, #37, #38, #39, #40, #41, #42, #43, #44；其中 **#25、#24、#35、#40 等是 CLOSED/NOT MERGED**，不可列成已導入 main；#39、#38 等 `merged_at` 有值，仍需查現行 main consumer。不能 Close 已經 closed 的 PR。

## 3. Open Issues（純 Issue 18 筆）逐項處置

| Issue | 能力／DoD 範圍 | 現況 | 判定 |
|---|---|---|---|
| [#4](https://github.com/easonliu714/my_finance_app_public/issues/4) | 帳戶捲動統計、分組與負債/多幣別語意 | CODE+DEVICE(PARTIAL)／CI FAIL | **KEEP**：4.20.28 只處理捲動/精簡，不包含帳戶分組及負債/多幣別全驗證 |
| [#5](https://github.com/easonliu714/my_finance_app_public/issues/5) | 常用帳戶/商家收藏及分組選單 | CODE/PARTIAL，具相關歷史 PR | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#6](https://github.com/easonliu714/my_finance_app_public/issues/6) | 簽帳卡授權與待清算生命週期 | CODE/PARTIAL，具相關歷史 PR | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#7](https://github.com/easonliu714/my_finance_app_public/issues/7) | 貸款提前清償模擬 | OPEN，需明確 DoD | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#8](https://github.com/easonliu714/my_finance_app_public/issues/8) | 全域通知樣式設定 | OPEN，需明確 DoD | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#9](https://github.com/easonliu714/my_finance_app_public/issues/9) | 電子票證儲值、建議與轉帳 | CODE/PARTIAL，具相關歷史 PR | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#10](https://github.com/easonliu714/my_finance_app_public/issues/10) | 交易表單快速新增帳戶/商家/分類 | CODE/PARTIAL，具相關歷史 PR | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#11](https://github.com/easonliu714/my_finance_app_public/issues/11) | 依時間預設消費分類 | OPEN，需明確 DoD | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#12](https://github.com/easonliu714/my_finance_app_public/issues/12) | 設定中心／Places／配額警示 | CODE/PARTIAL，具相關歷史 PR | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#13](https://github.com/easonliu714/my_finance_app_public/issues/13) | 統一發票中獎、官方同步、通知與獎金帳務 | CODE+DEVICE(PARTIAL)／CI FAIL | **KEEP**：獎金 POSTED 核心已驗，4.20.28 CI FAIL，官方時程/完整收款與剩餘 DoD 尚未閉環 |
| [#14](https://github.com/easonliu714/my_finance_app_public/issues/14) | 首頁自訂快捷鍵 | OPEN，需明確 DoD | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#15](https://github.com/easonliu714/my_finance_app_public/issues/15) | Actions 成本/快取/產物治理 | OPEN，需明確 DoD | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#16](https://github.com/easonliu714/my_finance_app_public/issues/16) | 商品照片 Gemini 辨識與人工審核 | CODE/PARTIAL，具相關歷史 PR | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#17](https://github.com/easonliu714/my_finance_app_public/issues/17) | 商品影像裁切與保存設定 | OPEN，需明確 DoD | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#18](https://github.com/easonliu714/my_finance_app_public/issues/18) | Schema 凍結/備份稽核/SQLite 加密 | OPEN，需明確 DoD | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#19](https://github.com/easonliu714/my_finance_app_public/issues/19) | 官方行事曆自動更新與 CSV 備援 | CODE/PARTIAL，具相關歷史 PR | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#22](https://github.com/easonliu714/my_finance_app_public/issues/22) | 低信心 OCR Gemini 自動補辨與精簡 UI | CODE/PARTIAL，具相關歷史 PR | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |
| [#28](https://github.com/easonliu714/my_finance_app_public/issues/28) | 語音自然語言記帳 | CODE/PARTIAL，具相關歷史 PR | **KEEP**：子功能原始碼/歷史 PR 不能替代原 Issue 的完整驗收 |

**結案結論：目前 18 張 Open Issues 沒有可憑本輪證據無條件 Close 的案件。** 應先逐一核驗 #22 / #16 / #28 / #9 與歷史 PR 的已完成子 Gate，再把剩餘 DoD 保留，不要為了降低 Issue 數而提前關閉父需求。

## 4. 已 Closed 的純 Issues 與是否需要重新開啟

- #20「商家歷史/官方登記/本地學習」：CLOSED，PR #43 merged；其全域驗收/新的資料問題應開新的明確子 Gate，不直接重寫商家核心。
- #29「商品多項辨識本地化與計算器」：CLOSED，PR #44 merged；禁止重複做相同計算器／商品辨識基礎。
- #32「發票確認結果移交正式交易草稿」：CLOSED；明確 Save 記帳契約保留，禁止繞過。
- 以上 CLOSED 不代表完全沒有後續 regression；但沒有本輪足夠證據要求 re-open。

## 5. 功能/Issue/PR Crosswalk（變更前必查）

| 功能 | Canonical owner | 既有 source | 相鄰 Issue／PR | 禁止重做 |
|---|---|---|---|---|
| 帳戶統計與列表 | #4 | account_detail_page.dart / account_page.dart | #5 #6 #9 | 不要再新增第二套期間推算或 account balance 表 |
| 發票兌獎 | #13 | invoice_award_production_page.dart / formal_income_posting_service.dart | PR #45 / #46 | POSTED 一筆一次，不重建獎號同步 |
| 商家與官方統編 | #20（CLOSED） | merchant/* registry_* / canonical_merchant_repository | #10 #12 | 不以公司總機構資料覆蓋消費店家識別 |
| 商品 AI | #16 | product/product_capture_page.dart / gemini_product_recognition_client.dart | #17 #29（CLOSED） | 不重新建立另一條 AI 直寫交易通道 |
| 語音輸入 | #28 | voice/voice_transaction_entry_page.dart | #10 | 不另建正式交易入口 |
| 帳戶儲值 | #9 | account/wallet_top_up_* | #6 | 保留來源/目的帳戶與人工確認 |
| 可讀備份與加密 | #18 | backup/* + production_schema_* | #12 | 不在 schema 尚未凍結時做破壞性 encryption migration |
| 通知/排程 | #8 #13 | invoice_award_runtime_scheduler.dart / plan/local_notification_service.dart | #19 | 不增加無治理的背景服務 |

## 6. 建議可執行的結案 SOP

1. 每個 Issue 綁 `OWNER/FEATURE_ID/CANONICAL_ENTRY/EXACT_SOURCE_BLOB/DDL_VERSION/API_EXTERNAL_AUTH/TEST_RUN/DEVICE_EVIDENCE/CLOSE_DECISION`。
2. `CLOSE` 只在原 DoD 全部 PASS 且殘餘任務已正式建立下一張追蹤時執行；`PARTIAL` 留 OPEN。
3. `merged_at=null` 必標 `CLOSED_UNMERGED`，不可視為 main 已交付；PR #45/#46 保持 Draft/OPEN，未經同意不 merge。
4. 確認 live current HEAD，特別留意本次源碼 ZIP 為舊版。
5. P0 先解 Run 38356246784 首個真正失敗測試，再更新 current-head CI；Canary 失敗是依賴性連鎖，不盲重跑。
6. 將本報告與第二份 UI/API/DB 樹設為每次交接的現況索引；新需求先搜尋 owner，再決定補強既有模組或開 Issue。

---
## 2026-10-13 結案更新（本節優先於舊快照的 PR 計數）

- GitHub owner 授權優先處理「可合併或可關閉」項目。完成交叉比對後，**PR #46 已 Closed / NOT MERGED**，歷史 head `df3ce39c1ae571bee900a8a49364baf2356c0aee`；結案依據見 https://github.com/easonliu714/my_finance_app_public/pull/46#issuecomment-6142590353 。
- PR #46 的 7 個 changed paths 為較舊的前景補更新/共用 process lease 候選，PR #45 已有 `invoice_award_runtime_scheduler.dart`, `invoice_award_automatic_refresh_runner.dart`, `invoice_award_app_lifecycle_coordinator.dart`, 原生 Android wake 與 notification runtime，且由 `lib/app.dart` 掛入。**功能責任被取代不代表檔案逐位元相同；禁止 cherry-pick 舊的兩套 SharedPreferences state**。
- **OPEN PR=1 (#45 Draft / merge HOLD), CLOSED PR=24**；純 Open Issues **18**，現階段沒有原 DoD 全 PASS 且可安全整張 Close 的 Issue。既有 closed 純 Issues #20/#29/#32 繼續保留，未以原 PR closure 重新打開。
- 最新 4.20.28+486 exact HEAD `43dfc02f5b78fa1900c7d83ba7b57d0b8888f5b2` 的 Flutter CI run `38356246784`：**1892 PASS / 12 FAIL**。其中 11 個失敗為 `4.20.27+485` 與 Lab validationVersion 未同步 `4.20.28+486` 的版本契約；另 1 個是 `invoice_award_check_route_test.dart` 仍要求「大型 PDF」說明預設顯示，但新 UX 需透過「？」開啟。真正 Signed Canary run `38356252713` 因 exact-head CI 未過而失敗，build/inspect SKIPPED；**不是簽章本身已驗證失敗**。
- 目前下一個唯一 P0 工程 Gate：最小修補 Lab 版本宣告、四處 release identity contract test，以及 Award Check Help 視窗操作測試。不得放寬正式收款、POSTED 交易冪等或背景授權限制。新 HEAD 必須重新 Flutter analyze/full test/APK + 真 signed canary，再可進實機。
- 本文件及 `docs/PROJECT_UI_API_DB_FEATURE_TREE.md` 是開發前的**重工預防與跨對話必讀**；任何新功能先確認五分頁入口、active service/SQLite schema、Owner Issue、目前 TEST/DEVICE 範圍，不得以文件存在等同實機已完成。

## 2026-10-13 4.20.28 第二輪 CI 根因與後繼修補

- Owner 的 6 檔第一輪手動熱修已由 GitHub 真實提交，最終第一輪 HEAD `3cf31619b688843c2057a40c572466ddcc9ab2e1`：原定 6 個檔案 6 commits / 無其他異動，來源 Blob 與交付修補一致；先前「需要上傳六檔」工作已 CLOSED，禁止重問。
- 第一輪後繼 Flutter CI [run 38381413843](https://github.com/easonliu714/my_finance_app_public/actions/runs/38381413843)：**1903 PASS / 1 FAIL**。真 Signed Canary [run 38381422288](https://github.com/easonliu714/my_finance_app_public/actions/runs/38381422288) 因 exact-head CI FAIL 而停止，Build/Inspect SKIPPED。失敗檔唯一為 `test/invoice_award_check_route_test.dart`，其一為 `DropdownButtonFormField` 在 800px 測試視窗有 **6.4px RenderFlex horizontal overflow**；其二測試要求「不上傳發票或記帳內容」常駐，但現行 UX 只在「開獎期別與官方來源」之「？」視窗呈現。
- 2026-10-13 已最小修補正式提交：production `lib/features/invoice/invoice_award_production_page.dart` `isExpanded: true`，commit `cf7a70678a41347ad415b0474e3efbea6f7b68ef`；Widget 測試改驗「主畫面無長文、開啟『？』才有來源隱私說明及大型 PDF」，commit `00e62a3e5fc51cba363b42bd7b7818d61aea3b53`。其他 4.20.28 功能與既有 transaction/POSTED 安全行為不變。
- 當前 Gate：`SOURCE_HOTFIX_COMMITTED`，但 **Flutter full-test、Signed Canary、APK SHA/簽章/權限與 4.20.28 owner 實機仍 PENDING**。任何修補 commit 或治理文件 commit 均廢除舊 HEAD 的 CI authority；最新 exact PR HEAD fresh-read 才可宣告驗證。
- Close-first 決議保持：PR #46 已 `CLOSED_NOT_MERGED`，PR #45 Draft/OPEN/Merge HOLD；18 張 Open 純 Issues 無可直接整張 Close；#4、#13 等待實機及原 DoD，勿重開已 PASS 發票獎金 POSTED NT$500+200=700 Gate。

## 2026-10-13 Signed Canary release-phase gate fix

- Exact earlier HEAD `36310c24445d440ecfdd93538660ae821c046199` Flutter Android CI [38384304123](https://github.com/easonliu714/my_finance_app_public/actions/runs/38384304123) **SUCCESS** (Analyze / full tests / debug APK). True Signed Canary [38384311754](https://github.com/easonliu714/my_finance_app_public/actions/runs/38384311754) at Validate stage **FAIL**: workflow `issue_13_invoice_award_mvp_signed_canary.yml` enforces actual `AppBuildMetadata.phase` prefix `issue-13-`, but 4.20.28 had `issue-4-account-geometry-issue-13-award-help-486`. This is exact release-identity disagreement, not production ledger regression; Signed Build/Inspect was SKIPPED.
- Minimal governed correction committed to **real** PR #45 code: `lib/app_build_metadata.dart` changes phase to `issue-13-award-help-issue-4-account-geometry-486` (both Issue #13 award help and Issue #4 accounts retained); three exact-phase tests updated, commits `e3f251687c64cf35fb47b98fda6a379633998a75`, `b4df8dae467a4fc0cf6d50ed18f30517e741eee0`, `5a0c991ef6a01c60762343ac8564025fb56fbb68`, `cda3e271887f81a58e31f62ddfeb720ff0a41582`. **No workflow safety gate weakened, no versionName/versionCode rotation**, still `4.20.28+486`.
- Current Gate after these commits: CODE=PASS, new exact-head CI/Signed Canary/Artifact/DEVICE=**PENDING**, cannot treat old 38384304123 SUCCESS as authority for changed HEAD. Latest PR HEAD must be fresh-read every round. Frozen owner accepted POSTED NT$500 + NT$200, no automatic duplicate/backfill or destructive SQLite changes. PR #45 OPEN/DRAFT/MERGE HOLD, PR #46 CLOSED_NOT_MERGED.

## 2026-10-13 Owner 實機驗證與 4.20.29 期別選單精簡

- **4.20.28+486 Owner 實機驗證回報 PASS（2026-10-13 20:35–20:37 Asia/Taipei）**。本輪附圖可獨立支持統一發票中獎檢查頁的「？」說明 Bottom Sheet 與授權更新、獎號狀態、通知/待入帳候選 UI 操作，安裝畫面亦顯示 App 版本 4.20.28+486。115-05-06 可見 29 筆候選、一般獎 0、雲端號碼吻合 1；115-07-08 可見 47 筆候選、一般獎 1、雲端號碼吻合 0。截圖為 UI 使用證據，不額外推論銀行 API 回讀、實際收款、完整 DB parity，亦不作為 Issue #4 全帳戶長列表滾動測試的獨立證據。**Issue #13 Award UI DEVICE=OWNER PASS，Issue #4 其他 DoD 保留待驗**，PR #45 仍 DRAFT / MERGE HOLD。原 4.20.28 exact head `2130d43c8e97170d3bb1542d10923bcb57bb47c5` Flutter CI [38385975603](https://github.com/easonliu714/my_finance_app_public/actions/runs/38385975603) 與真 Signed Canary [38385984866](https://github.com/easonliu714/my_finance_app_public/actions/runs/38385984866) 均 SUCCESS。
- Owner 新增 UI 改善：**期別 Dropdown 只顯示 `115年07-08月`，兌獎資訊 `兌獎資訊：兌獎期間內（至 2027-01-05）` 獨立顯示於下方**。切換期別需同步更新下方 status；長篇官方來源、隱私、PDF 額外操作說明仍由「？」 Bottom Sheet 展開。
- 為保護已驗收的 4.20.28 證據，將新增 UI 收斂在 `4.20.29+487`、release phase `issue-13-award-period-selector-487`。實際程式已將 `InvoiceAwardProductionPage` 選項從 `option.menuLabel(now)` 改為 `option.periodLabel`，下方文字保留 `_selectedPeriod.statusLabel(now)`；`test/invoice_award_check_route_test.dart` 明確檢查 DropdownMenuItem 無『兌獎』字樣與下方期限狀態。其餘 release identity / LAB validationVersion / canonical test contracts 同步進版。無 DB schema、正式帳務/入帳服務或背景權限改動。
- **4.20.29 狀態：SOURCE COMMITTED；Flutter CI / True Signed Canary / APK SHA+Signer / OWNER DEVICE 仍 PENDING，絕不可用 4.20.28 的成功當成 4.20.29 的成功。** 對新 HEAD 提交完治理文件後，以最終 exact-head Run 為準。保留 POSTED NT$500 + NT$200=700 的既有稽核成果，禁止重複入帳或自動補登。

## 2026-10-13 4.20.29 Flutter Analyzer Regression 修補

- 4.20.29+487 首次完整 Flutter CI [38400071955](https://github.com/easonliu714/my_finance_app_public/actions/runs/38400071955) 為 **FAIL / Analyze Dart code**，其 first/only analyzer error：`test/invoice_award_check_route_test.dart:31:35` 使用 `DropdownButtonFormField<String>.items`，但此欄位沒有可供 Widget 測試存取的公開 getter。該 CI 停在 Analyze，不能宣稱 production UI FAIL 或 1904 套件測試已執行。Signed Canary [38400082235](https://github.com/easonliu714/my_finance_app_public/actions/runs/38400082235) 因 exact-head CI authority FAIL，Build/Inspect SKIPPED。
- 已完成**唯一測試檔最小修補** commit `e009331a420cceccb5a3286394974aa3b4e20a44`：原主測試僅核對選定期別+獨立兌獎資訊；新增第二個 Widget test 使用 `tester.tap` 真實開啟 Dropdown，核對 `115年07-08月` / `115年05-06月` 期別選項，禁止存取不存在的 Flutter API。正式 UI、Domain、API、SQLite/ledger 未改動。
- 此次 **4.20.29 CODE=PASS; fresh exact-head Flutter Analyze/Full tests/Debug Build/Signed Canary/Owner Device=WAIT**，不可繼承先前 4.20.28 綠燈。4.20.28 原 Owner Award UI PASS 仍保留，不回退。PR #45 仍 OPEN/DRAFT/MERGE HOLD，並保持 POSTED NT$500+200=700 防重複、不自動回填、明確正式記帳授權。

## 2026-10-13 Owner 4.20.29 合併實機驗證 Gate — 期別說明外置及 Issue #4

- Owner 同意將「開獎期別」問號說明按鈕移到 Dropdown 框外右側，不能與期別或下拉箭頭重疊，並將下一個已排定且可安全一併驗收的 Gate 放在同一版 4.20.29+487。原 4.20.28 Issue #13 Award UI OWNER DEVICE PASS 保留不重跑。
- Production：lib/features/invoice/invoice_award_production_page.dart 移除 InputDecoration.suffixIcon，改成 Row（key=invoice_award_period_selector_row），包含 Expanded/DropdownButtonFormField（key=invoice_award_period_selector，isExpanded=true）、8px 間隔，以及原問號 Help IconButton。Dropdown 選項仍只顯示 periodLabel，獨立期限資訊繼續在選單下方，保留原 Help Bottom Sheet 全文、period.id、canCheckAt、官方 API、通知、正式入帳授權與 SQLite。
- Focused test：test/invoice_award_check_route_test.dart 新增 360px 寬度 Widget case，斷言同一 Row 裡的外置按鈕不屬於 Dropdown descendant、實際框線不重疊、Help 右緣沒有超出螢幕、點問號仍看得到 PDF 官方說明。任何新 Flutter CI 必須以最新 unchanged exact HEAD 判定，4.20.29 SOURCE COMMITTED 不等於自動測試／Signed／Owner DEVICE 已 PASS。
- **下個原定 Gate 一併實機驗收但不重寫功能**：Issue #4 全球共用帳戶明細的長卡片精簡、來源／稽核資訊展開，以及依第一筆真實可見交易的日期同步年／月摘要。4.20.28 已有相關 production code，因此在 4.20.29 併入同一份 Owner UAT 而非新增重複邏輯。未完成的帳戶群組、信用／貸款細節、跨幣別總表、新的首頁快捷鍵不得為追求同一版硬塞入範圍。
- Combined Owner Gate A／發票：在 115-07-08 與 115-05-06 切換，選單只見期別、下方兌獎期限同步、問號在框外右側、不截斷不覆蓋，Bottom Sheet 正常，保護舊 POSTED NT$500+NT$200=700、不補登。Gate B／Issue #4：至少銀行與一卡通 Money 電子錢包各一組手機截圖，09/11→09/21→09/24 同月份長列表捲動後 2026年/09月 年月和統計數值不因卡片高度無故跳動，展開稽核資訊／反向捲動定位穩定，跨月與 2026/12→2027/01 時兩摘要同步（若欠缺真實跨年資料，保持待驗或用不改正式資料的可控 fixture）。其他帳戶類型與原 Issue #4 DoD 繼續追蹤，不能用兩帳戶樣本直接全數 Close。
- 現行 PR #45 仍 OPEN/DRAFT/MERGE HOLD；舊 PR #46 CLOSED_NOT_MERGED。原 Issue #4/#13 保持 OPEN 直到完整 DoD，不可混用 UI Pass 與銀行 API / DB 正式帳務 Pass。每個版本／Gate 更新需同步本 Roadmap 與 PROJECT_UI_API_DB_FEATURE_TREE.md。

## 2026-10-13 22:32 Owner 4.20.29 聯合 Gate PASS、4.20.30 年度標題下一 Gate

- Owner 提供 5 張 Android 實機截圖並明確回報 **4.20.29+487 聯合實機 Gate PASS**。Issue #13：開獎期別下拉選單只顯示 `115年07-08月`、問號說明圖示在框外右側無重疊、兌獎資訊在選單下方（至 2027-01-05）；自動更新、通知及記帳準備開關 UI 保留。Issue #4：一卡通 Money 2026/05 與 2026/08 的明細已精簡且月份摘要跟隨畫面交易；中國信託 5445 顯示 2026 年本地正式帳戶餘額 700 TWD、兩筆既有發票獎金 200+500 TWD，日期 2026/10/06 及 2026/08/06。上述屬於手機 UI/本地記帳畫面證據，不代表銀行 API 回傳或完整 DB 檢查。
- **仍有重要可見殘餘：** 一卡通 Money 左側年度摘要在窄螢幕顯示 `20...` 而不是 `2026年`。不得把 4.20.29 Owner PASS 誤解成完整 Issue #4 年份標題／所有帳戶種類／跨年／可存取字級的 DoD PASS。
- 下一原定實作 Gate 已由分支開始為 **4.20.30+488 / phase issue-13-accepted-issue-4-summary-title-488**：`_CompactPeriodSummaryCard` 將標題和淨額改為各自獨立列、`FittedBox(fit: BoxFit.scaleDown)` 避免 `2026年` 因金額過長被截斷；保留 inflow/outflow 的合理省略號、原聚合運算及 Ledger。這是排版修正而非資料修正。
- 首個 4.20.30 exact-head PR `9a7c3a7a79db515549023d99265b47fb836f9161` Flutter CI [38412520575](https://github.com/easonliu714/my_finance_app_public/actions/runs/38412520575)：**1906 PASS / 1 FAIL**。第一且唯一失敗在 `test/issue_4_issue_13_4_20_28_ux_contract_test.dart` 的靜態契約誤把整張摘要卡的支出／收入明細 `TextOverflow.ellipsis` 視為年份標題被截斷。Signed Canary [38412534273](https://github.com/easonliu714/my_finance_app_public/actions/runs/38412534273) 因 exact-head CI 未通過而 FAIL，Build/Inspect SKIPPED。此失敗與實際帳本值無關。
- 最小修補已提交：`test/issue_4_issue_13_4_20_28_ux_contract_test.dart` 將禁用省略號的檢查限定在 `summary.label` 至下一個 SizedBox 間的年份標題 Widget；保留完整標題不可 ellipsis、獨立排版和 BoxFit.scaleDown 的契約，不放寬收入支出明細正常截斷。**新版 exact HEAD CI/Signed Canary 待驗證；4.20.30 尚不可實機。**
- 主體策略：PR #45 OPEN/DRAFT/MERGE HOLD，#46 CLOSED_UNMERGED；Issue #4/#13 保留未完成全 DoD；不重新登記 NT$500+200 舊收入、不改正式資料或 SQLite。後繼 Gate 以 Issue #4 全帳戶年份/月份分離顯示之手機驗證為優先（一卡通 Money 長幣別＋負值、銀行 700 TWD、橫向不截字、跨年及動態大字體仍需證據）。重要變更應同步更新本文件與 `PROJECT_UI_API_DB_FEATURE_TREE.md`。

## 2026-10-14 00:37 Owner 4.20.30 PASS / P0 完整備份回歸修補 4.20.31

- Owner 使用 Android 4.20.30+488 實機截圖明確確認年／月分列摘要、iPASS Money 負值及八月／九月統計隨可見交易定位，銀行帳戶既有兩筆獎金 +500／+200 (=700) 不變，**4.20.30 Issue #4 年度標題 UI 局部 Gate PASS**。這不等於帳戶跨年、所有類型、全 DoD 或銀行 API 狀態均已驗證；Issue #4/#13 保留 Open，PR #45 DRAFT/MERGE HOLD。
- 同批次新發現 P0 回歸：`我的→完整備份／完整還原→建立完整備份` 顯示「檔案操作失敗：未知資料表：expense_categories」。真實原始碼核查：分類 repository 動態 `ensureExpenseCategorySchema()` 建立使用者資料表，但 `FullBackupScope` Scope V8 沒收錄；其 `inspect()` 會嚴格阻斷所有未知表。此檢查本身是合理防遺漏措施，**不可將 expense_categories 放入 excluded 或刪除表、清空資料庫、關閉嚴格 Gate**。
- 新修補版本：**4.20.31+489**，phase `issue-13-accepted-issue-4-backup-scope-v9-489`（Signed Canary issue-13- release phase gate 不降低）；Scope V9 在既有 Scope V8 的使用者商家身分表後，新增受管 `expense_categories`，保留分類 ID／自訂名稱／排序／封存／時間欄。原 SQLite canonical schemaVersion=24 沒更動，分類表保持原本 lazy schema，沒有主動修改實機財務資料。
- 還原一致性：`FullRestoreService` 在明確輸入 RESTORE 且來源驗證後、正式 transaction 內執行 `ensureExpenseCategorySchema(txn)`，確保新裝置還原分類行不會因缺表被默默跳過，失敗會 transaction rollback；`FullRestoreServiceV8` 只把 pre-V8 轉為 V8，不會將原 V8 merchant identity/history 重算覆寫。備份預覽及還原 manifest 按 Scope V2–V8 各自舊表清單驗證，Scope V9 要求包含分類陣列，未知自有資料表仍 fail-closed。
- 新增 `test/expense_category_full_backup_scope_v9_test.dart`，涵蓋 V9 自訂分類完整匯出、新裝置還原、舊 V8 商家資料保留、未知表阻斷、V9 缺分類陣列拒絕還原。既有 Scope V8 fixture 版本斷言與 App 4.20.31 release identity/Lab 契約同步。
- **本階段只有 SOURCE/TEST CODE COMMITTED；最新 exact-HEAD Flutter Analyze/full tests/debug APK／true Signed Canary／Signed APK SHA+簽章／Owner 新機建立備份／測試還原預覽仍 PENDING**。未確立匯出及還原驗證前不得標記 P0 CLOSED，也不得合併主線；禁止在真實手機執行完整覆寫還原以測試功能。首先驗證生成備份 JSON metadata Scope V9 及 expense_categories 不為空（若裝置原有分類），再以隔離空白測試 DB 預覽、受控還原與 count/parity 證據；最後 Owner 在實機僅點「建立完整備份」確認成功，保存並核對 ZIP/JSON。

## 2026-10-14 01:47 — 4.20.31 Owner PASS／4.20.32 Issue #4 分組語意

### 已接受的前繼 Gate — 4.20.31+489 備份／還原

- **2026-10-14 01:47 +08 Owner 明確回報 4.20.31「帳戶備份與還原成功」，允許推進下一階段。** 可將先前因 expense_categories 不在備份 Scope V8 的 P0 回歸標為 OWNER_DEVICE=PASS（本次回報之備份/還原流程），禁止重做已實現 Scope V9。
- 正式驗證依據：HEAD `e9a62d549cf37dcfa01e70c909fd942a58d6e66c`，Flutter Android CI [38433579674](https://github.com/easonliu714/my_finance_app_public/actions/runs/38433579674) **SUCCESS**、真正 workflow_dispatch Signed Canary [38433592413](https://github.com/easonliu714/my_finance_app_public/actions/runs/38433592413) **SUCCESS**。Scope V9 應保留 expense_categories、舊 Scope V8 合法讀取、嚴格未知表 fail-closed 及 transaction rollback；無新手機資料破壞。本次 Owner 回報不能外推成 Issue #18 的 schema freeze、所有跨版／冷開機災難復原或 SQLCipher encryption PASS；Issue #18 仍 OPEN，延後到原 Roadmap 所訂最終 Gate。
- 原 4.20.30 年度摘要標題 Owner PASS（歷史 snapshot）；既有 POSTED 獎金 NT$500 + NT$200 = NT$700 不重複寫入、不 background backfill。#45 Draft/OPEN/Merge HOLD，#46 CLOSED_UNMERGED。

### 下一個原定 Gate — Issue #4 帳戶群組餘額語意（4.20.32+490）

- 對照 Issue #4 [原 DoD](https://github.com/easonliu714/my_finance_app_public/issues/4) 與 CODE：`AccountPage` 既有 `_groupAccounts()`、`_AccountTypeSection` 和 `_collapsedTypes`，類型分組和展開/收合已有實作，**禁止再建第二套分組 UI**。
- 實際缺口：原群組摘要文字用「TWD 換算淨額」，但程式只是把各帳戶的 `currentBalance * CurrencyCode.defaultRateToTwd` 直接相加；信用卡帳面餘額不等同待繳款／可用額度，借貸不等同未償本金，投資不等同市值，非 TWD 匯率為內建參考值、非即時。不得偷偷把此數字當淨資產或修改正負號補帳。
- 新版 `4.20.32+490`（phase `issue-13-accepted-issue-4-group-semantics-490`）只修改 UI 解說：`AccountGroupBalanceSemantics` 依 type 提供 creditCard／loan／investment／一般帳戶的簡短語意與非即時外幣提示；`AccountPage` 只更新總覽／群組小標題，**保留既有 sum、帳戶順序、收合控制、Reference FX 與 SQLite 完整未變**。新 `test/account_group_balance_semantics_test.dart` 測正向／負債／外幣展示契約；版本、Lab validationVersion、release tests 同步進版。
- **當前僅 SOURCE COMMITTED / Flutter CI=NEW EXACT HEAD PENDING / 真 Signed Canary=PENDING / 新 APK SHA signer=PENDING / OWNER DEVICE=PENDING。** 無新版本 CI 證據前不可宣稱 4.20.32 READY。
- Owner 實機 Gate：帳戶首頁按類型展開／收合、銀行＋一卡通 Money、信用卡／借貸（若現存可驗）、非 TWD 群組文字；核對數字不變／Reference FX 標籤／沒有將負債寫成淨資產。沒有必要的帳戶類型時保留待驗，用隔離 fixture 測試，不新建真實金流。
- Issue #4 的實機文字語意 Gate 過後仍需依原 DoD 稽核信用卡、貸款、投資及混合幣別的真實餘額定義；不因標籤補強就整張 CLOSE。Issue #13 保留原未完成項目；Issue #18 Encryption 保留最終階段。

## 2026-10-14 09:07 Owner 4.20.32 PASS／雲端 500 Worker 鎖屏回歸與其他獎別搜尋

### 4.20.32 已接受的實機分組 Gate

- Owner 七張 Android 實機截圖明確表示 4.20.32+490 **帳戶群組顯示／展開收合 PASS**。現金 -148 TWD；銀行 2 帳戶彙總 700 TWD（舊 0、新中國信託 5445 700）；信用卡 -75 TWD，仍顯示帳面餘額非待繳款或額度。原 POSTED 500+200=700 維持，不得重新補登。**僅受截圖支持的 UI Gate PASS**；其他帳戶/外幣及完整 Issue #4 DoD 仍 OPEN。
- GitHub exact 4.20.32 HEAD `2c90c14eccbd43771db795420aa9774389854090` Flutter Android CI [38442351717](https://github.com/easonliu714/my_finance_app_public/actions/runs/38442351717) **SUCCESS**、真正 workflow_dispatch Signed Canary [38442361870](https://github.com/easonliu714/my_finance_app_public/actions/runs/38442361870) **SUCCESS**。此舊 HEAD 不能替代後繼修補的 CI。

### 新 P0 Owner 回歸：115-07-08 雲端專屬 500 元獎 Worker 在來源 SHA 階段終止

- 新手機重新下載發票／比對後，於 2026-10-14 約 08:08–08:17 +08，Owner 截圖表明 cloud-500 `CLOUD_AWARD_CANDIDATE_WORKER_PROCESS_DIED_PLATFORM_SOURCE_SHA256`，App 回報「本次雲端專屬獎更新不完整，保留既有 LKG」。這是一個**真實 OWNER FAIL**，先前 4.20.32 已完成的帳戶分組 Gate 不應因此翻為 FAIL。
- 客觀階段：官方 500 PDF 128.9 MiB（135,200,798 B）已下載/緩存、診斷結構顯示 PDF 1.5、`xrefStream`、`raw_candidate_hits=0/47`（只表示壓縮 raw window 看不到候選號碼，非查無中獎）、之後 Android platform PdfRenderer **獨立前景 Service** 在 **重新串流確認 PDF SHA-256** 階段進程死亡，**尚未完成候選二分搜尋**。Owner 觀察鎖屏時間相近，但 OS 的 low-memory、ANR 或背景政策等 **具體死因尚無證據**；不可宣稱已證明鎖屏是唯一根因。
- 既有 500 最佳化並非缺失：`PdfiumCloudAwardSortedPdfCandidateLookup` 已對官方 sorted 500 PDF 用 exact on-device candidates + binary page search，且 120 MiB 以上使用 `PlatformPdfCandidateWorkerService` 隔離（Android API 35+）；**500 元並非逐頁全量索引**。其他三獎 `cloud-800` (100,000 rows)、`cloud-2000` (16,000)、`cloud-1000000` (30) 目前走 `CloudAwardPdfIndexBuilder.buildCandidate` 完整逐頁建立索引；三者也取得 `_sorted_` 官方 PDF，技術上可導入直接候選搜尋，但不得以 PDF raw byte 字串檢索或單次命中推出完整「未中獎」權威。
- Current successor **4.20.33+491** `issue-13-cloud-worker-screenoff-491` 已 CODE COMMITTED，對 platform worker 的前景 Service 任務加入 **30 分鐘上限 PARTIAL_WAKE_LOCK**（Manifest 顯式 `android.permission.WAKE_LOCK`，完成或失敗 finally release）；Android 30+ 原始 PID 的 ApplicationExitInfo exitReasonCode 只作死亡診斷，失敗字串可加 `_OS_EXIT_<code>`。醒著不代表不會因 LMK/系統限制被終止，絕不得改成「Lock screen 不會中斷保證」。保留完整官方 PDF SHA／候選 universe SHA、LKG fail-closed、分階段的原生檔案證據與獎金人工授權流程，不改 DB/正式 POSTED。
- 新增 `test/features/invoice/invoice_award_cloud_lifecycle_contract_test.dart` 防退化斷言，Lab / pubspec / build metadata / 四份 release 契約對齊 4.20.33。**最新 exact HEAD Flutter Analyze/full tests/debug APK=待新 CI；Signed Canary/簽章/Owner 鎖屏實機=待驗，不可把 4.20.32 GREEN 外推為 4.20.33 成功。**
- 4.20.33 UAT：同批 115-07-08、47 候選、官方 500 PDF 128.9MB，螢幕亮著對照一次、鎖屏 1–3 分鐘後回 App 一次；需 native worker 仍進度且 source SHA pass、在已排序 PDF 只讀少量候選頁；若失敗檢查同一錯誤 stage + `OS_EXIT` 診斷，不要求使用者關閉全域電池保護或無限制開放背景權限；依實際平台保護限制決定是否 HOLD。保留 800/2000/1000000 LKG。不得要求重複正式入帳。
- **下一個原定 P1 功能 Gate**（與 4.20.33 隔離版本，避免同時改兩種失敗面）：將候選範圍 exact match / 官方 sorted PDF 二分查找擴展至 `cloud-800`、`cloud-2000`、`cloud-1000000`；先有各 tier 實際官方 PDF fixture 與全量 index parity、上下界與相鄰頁/負例、source URL+SHA+length+candidate-universe SHA+page evidence 與 FAIL-CLOSED 恢復證據，然後再打開分流；不得將單純 `raw_candidate_hits=0` 當「未中獎」或直接略過 PDF source authority。既有 500 搜尋與一般獎邊界不變。
- PR #45 DRAFT/OPEN/MERGE HOLD；Issue #13 仍 OPEN 且標記 cloud 500 worker 回歸；Issue #4 已完成分組顯示的特定 Owner Gate，但原完整多幣別/借貸 DoD 仍 OPEN；Issue #18 留待最後 schema freeze/encryption。

## 2026-10-14 10:57 Owner 4.20.33 鎖屏存活 PASS、完成時間 HOLD → 4.20.34 階段可觀測性

- **OWNER 実機觀察（10:47–10:56 +08，六張 Android 截圖）**：版本畫面 `4.20.33+491`，官方期間 115-07-08，既有發票候選 47 筆，一般獎官方來源已驗證、舊一般獎中獎 1 筆；cloud-500 重用 135,200,798B、PDF structure SHA `f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571`，`raw_candidate_hits=0/47`（原始壓縮 window 診斷，**不是中獎陰性判定**）。切到其他 App 或自動鎖屏並返回，背景服務至少在截圖期間沒有顯示先前的 PROCESS_DIED；**屏幕關閉不中斷的本次觀察：Owner PASS**。但啟動後超過 5–8 分鐘尚無 candidate search 最終完成或失敗之輸出：**latency/completion Gate HOLD**，不得稱 4.20.33 雲端500 Gate 完整 PASS 或 LKG 已更新。
- **精確 GitHub Gate**：4.20.33 latest accepted code head `d73adbf97000e2734f81d7a35d2646359b65e844`，[Flutter Android CI #38494727258](https://github.com/easonliu714/my_finance_app_public/actions/runs/38494727258) SUCCESS，[真正 workflow_dispatch Signed Canary #38494734813](https://github.com/easonliu714/my_finance_app_public/actions/runs/38494734813) SUCCESS。APK 版本身份由 Owner 截圖證實；本次還沒有完整完成的雲端500結果，不能外推為 performance PASS。
- **原始碼診斷**：`PlatformPdfCandidateWorkerService` 在 `PLATFORM_SOURCE_SHA256` 重新核對完整 128.9MB source；`PLATFORM_RENDERER_OPEN_BEGIN/WAIT` 透過 Android platform `PdfRenderer` 開啟 87,000 頁官方 PDF；`PLATFORM_RENDERER_PAGE_BEGIN` 再讀取已排序頁面並查 47 個候選。Flutter `InvoiceAwardProductionPage.didChangeAppLifecycleState(resumed)` 先前會將實際 Worker 階段字串**覆蓋成泛稱「正在同步背景雲端獎比對進度與結果」**，故當前截圖無法辨別真正耗時是 source hashing／`PdfRenderer` opening／page fetching／search。不得根據畫面停留 8 分鐘直接推斷 CPU、OOM 或永久卡死，也不得把 Android 系統前景服務的存活等同資料已驗證完成。
- **新實作 4.20.34+492（phase `issue-13-cloud-worker-stage-telemetry-492`）**：僅 UI diagnostic 字串／生命周期階段展示；回到 App 顯示最後收到的實際 Worker 階段與「尚未完成驗證」，而非 generic sync；分別呈現 `PLATFORM_RENDERER_OPEN_OK`、`PLATFORM_RENDERER_PAGE_BEGIN`、`PLATFORM_RENDERER_CANDIDATE_SEARCH` 的 native 階段、候選編號、已讀頁數與 elapsed。原生 Worker、原生 SHA、原本 PDF 檔、驗證失敗 fail-closed、候選集合與 POSTED 500+200=700 均未更動。同步擴展 `test/features/invoice/invoice_award_cloud_lifecycle_contract_test.dart` 的階段不回退保護，旋轉版本與 release contracts。**新 HEAD Flutter CI／Signed Canary／Owner Device 均待完成，不能標為 READY**。
- **4.20.34 最小 Device Gate**：進入 115-07-08 同一份已緩存 PDF，不重覆刪除/下載；每隔約 1–2 分鐘記錄「驗證官方 PDF N MB」「Android PDF 引擎開啟 elapsed」「正在讀取第 N 頁」「候選 N/47、已讀 N 頁」及該階段實際時間。若超過約 5 分鐘仍不變，確認**具體階段**，如看到明確終止碼則記錄，但不要在不清楚情況時反覆重啟或放寬 SHA／逾時。只有完整候選搜尋、真實來源／頁面證據和 LKG successful promote 才能 PASS。
- **後續效能優化決策**：先用 4.20.34 證據找主要瓶頸。若 `PLATFORM_RENDERER_OPEN_WAIT` 耗時最大，優先研究 87k-page PDF lazy opening／官方排序頁讀取瓶頸，不能僅加大等待時間；若候選搜尋耗時最大，考慮 47 筆候選批量分區與頁 cache reuse，需相對既有方法的全陰陽性與邊界 parity；若 SHA 慢，盤點現有下載 SHA、structure probe SHA 與 Worker SHA 之可證明來源/不可變 cache 的重複性，在完整 provenance 無損前不可略過任何 Gate。other tier candidate-scoped plan 繼續待批准 parity Gate，不在 4.20.34 混做。
- PR #45 Draft/OPEN/Merge HOLD，Issue #13 OPEN。不要將 Owner 本次「鎖屏不會中斷」誤標為來源/候選「完整成功」。兩份正式治理文件與 GitHub PR/Issue 記錄更新於同一活躍 branch；不回寫 main。
