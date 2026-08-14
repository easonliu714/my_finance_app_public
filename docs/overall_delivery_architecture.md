# Overall Delivery Architecture Viewer

最後更新：2026-06-13  
階段：P4.10.22 Overall Delivery Architecture Viewer  
Issue：#378

---

## 1. 目的

本文件用來對焦 My Finance App 最終交付給使用者時的完整產品範圍。它不是單一功能需求，而是後續實作、驗收與 APK 測試的總施工圖。

本階段先以文件與 Mermaid 圖形成共識，再決定後續 issue 優先順序。

---

## 2. 產品定位

My Finance App 是 local-first 的個人記帳 App，核心價值是：

- 日常記帳快速、清楚、可追溯。
- 帳戶、交易、信用卡分期、還款計劃互相關聯。
- 發票、商品拍照、AI 與 Google Places 都只作為候選資料來源，進入人工審核後才可成為正式紀錄。
- 備份、還原、匯入、匯出都需可預覽與可確認。
- API key、雲端發票、AI、Places、計劃設定集中於「我的」頁設定中心。

---

## 3. 五大分頁總覽

| 分頁 | 產品角色 | 主要功能 | 主要資料來源 |
|---|---|---|---|
| 帳戶 | 資產與付款來源管理 | 帳戶清單、新增帳戶、帳戶事件、帳戶明細、信用卡帳單關聯 | accounts, account_events, transactions |
| 計劃 | 未來付款與分期管理 | 信用卡分期、還款計劃、固定支出、貸款還款 | credit_card_installment_plans, schedule_items, repayment plans |
| 首頁 | 每日操作入口 | 本月摘要、compact shortcuts、日常紀錄、月預算、待審核提醒 | transactions, budgets, invoice drafts, image staging |
| 報表 | 查詢與統計 | 帳單明細、月/年/全部期間、收支趨勢、類別/帳戶/商家分析 | transactions, accounts, categories, merchants |
| 我的 | 設定與資料治理 | 備份還原、readable 匯入匯出、通知、設定中心 | backup settings, API settings, cloud invoice settings |

---

## 4. 首頁快捷鍵定義

首頁 compact shortcuts 是使用者日常最常用入口。

| 快捷鍵 | 預期功能 | 對應路由 / 後續目標 |
|---|---|---|
| 速記 | 直接開啟一般記帳新增流程 | TransactionEntryPage |
| 發票 | 開啟手輸入發票 / 掃發票入口，短期先進手輸入發票 | ManualInvoiceEntryPage |
| 拍照 | 進入拍商品 / 拍收據 / 影像候選入口，需接 staging review | 後續 Capture Entry route |
| 還款 | 開啟計劃還款入口，首次開啟也必須主動載入信用卡、分期與借貸資料 | PlanPaymentEntryFlow |
| 對獎 | 開啟發票對獎入口；開獎日下午約 15:00 後確認官方資訊可用並提醒使用者對獎 | 後續 Award Checking route / #380 |

原先首頁快捷鍵「全部」會進入完整帳單明細，但底部「報表」分頁已承接完整帳單與統計查詢，因此首頁不再需要重複一個「全部」入口。若後續需要更多功能，應另設「更多」或放入「我的 > 設定中心」。

---

## 5. 技術架構分層

```text
UI / Routes
  -> Riverpod providers / app services
    -> local repositories / DAO
      -> SQLite / sqflite
    -> external adapters, user-triggered only
      -> Gemini / Google Places / official portal handoff / device resources
```

### 5.1 UI / Route 層

- 五大分頁固定：帳戶、計劃、首頁、報表、我的。
- 每個功能入口都需對應 route name、可測 key 或穩定文字。
- 開發階段卡片不得直接暴露在正式頁面；未完成能力應以正式文案標示狀態。

### 5.2 Provider / Service 層

- 日常帳本由 transaction providers 聚合。
- 發票、影像、AI、Places 必須走 staging / candidate / review service。
- 發票對獎必須走 announcement availability check、candidate matching、review result，不得自動執行領獎或雲端同步。
- 還款入口必須自行初始化計劃/帳戶資料，不得依賴使用者先進入「計劃」頁。
- 設定中心管理 API key、配額警示、雲端發票設定、計劃設定。

### 5.3 Local data 層

- 帳戶、交易、信用卡分期、發票草稿、影像候選、API 設定、備份設定需可追溯。
- 正式紀錄與候選資料不可混淆。
- 發票 / AI / Places 的結果需保留來源、狀態、review record。

### 5.4 External resources

| 資源 | 用途 | 安全邊界 |
|---|---|---|
| Gemini / Google AI Studio | 圖像理解、商品與發票候選解析 | 使用者輸入 key；手動測試；結果進候選審核 |
| Google Places | 商家 / 地點候選查詢 | 使用者輸入 key；費用/次數警示；手動觸發 |
| 財政部雲端發票 / 官方平台 | 發票查詢、官方入口、對獎治理 | 先以官方入口與使用者交接為主；不保管帳密；對獎資訊確認後只提醒與產生可審核結果 |
| Android camera/gallery | 拍商品、拍收據、選圖 | 權限由使用者觸發；建立本機候選項目 |
| Android notification | 備份提醒、開獎提醒 | 本機提醒設定；可關閉 |
| File picker / share sheet | 備份、還原、匯入匯出 | 預覽與確認後執行 |

---

## 6. 後續優先順序建議

本 viewer 合併後，建議重新排序：

1. #381 Home Repayment Shortcut Lazy Load Account Data
2. #369 Manual Invoice Payment Account Dropdown
3. #370 Manual Entry List Refresh
4. #380 Home Award Checking Shortcut and Reminder
5. #376 My Page Settings Center
6. Capture Entry route for photo/product shortcut
7. Invoice staging / scan flow integration
8. Places merchant candidate flow
9. Report charts and filters
10. Release candidate APK end-to-end validation

---

## 7. APK 驗證原則

每次影響 visible UI、route、資料寫入、外部資源設定、備份還原的 PR 合併後，都需要明確列出 APK 驗證項目。若只是文件 viewer，可不要求功能 APK，但合併後需用它作為後續 APK checklist 的依據。
