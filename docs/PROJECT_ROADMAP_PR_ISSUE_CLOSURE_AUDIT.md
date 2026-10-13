# 記帳軟體 Roadmap／PR／Issues 結案稽核與防重工治理

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
